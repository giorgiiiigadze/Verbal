//
//  QuoteService+Quotes.swift
//  Verbal
//
//  Quotes themselves: reading the list, saving a new one, duplicating,
//  deleting, and every edit that rewrites a column on the row.
//

import Foundation
import Supabase

extension QuoteService {
    /// Fetch the signed-in user's quotes, newest first.
    static func fetchQuotes() async throws -> [QuoteSummary] {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let response: PostgrestResponse<[QuoteSummary]> = try await client
            .from("quotes")
            .select("id, title, job_summary, total, status, created_at, currency, pinned, scope, number, validity_date, subtotal, tax_rate, tax_amount, customers(name)")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
        // Keep the bytes, not the models — the next launch decodes them the
        // same way and shows this list before the network is even reachable.
        LocalCache.save(response.data, for: .quotes, userID: userID)
        return response.value
    }

    /// Persist an already-generated quote (from `generate`) with its transcript.
    @discardableResult
    static func save(_ quote: GeneratedQuote, transcript: String, title: String,
                     currency: String, clientName: String = "") async throws -> UUID {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }

        let customerId = try? await customerID(named: clientName, userID: userID)

        // Deterministic totals (never trust the LLM for math).
        let subtotal = quote.lineItems.reduce(into: 0.0) { sum, item in
            if let total = item.lineTotal { sum += total }
        }

        // Fall back to the AI summary as the quote's name when the user didn't type one.
        let typedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = typedTitle.isEmpty ? quote.title : typedTitle
        let quoteInsert = QuoteInsert(
            userId: userID,
            title: resolvedTitle.isEmpty ? nil : resolvedTitle,
            jobSummary: quote.jobSummary,
            scope: quote.scope,
            notes: quote.notes,
            subtotal: subtotal,
            taxRate: (try? await BusinessService.fetch())?.defaultTaxRate ?? 0,
            status: "draft",
            currency: currency,
            customerId: customerId ?? nil
        )

        let inserted: InsertedRow = try await client
            .from("quotes")
            .insert(quoteInsert, returning: .representation)
            .select("id")
            .single()
            .execute()
            .value
        let quoteID = inserted.id

        let lineItems = quote.lineItems.enumerated().map { index, item in
            LineItemInsert(
                quoteId: quoteID,
                description: item.description,
                type: item.type,
                quantity: item.quantity,
                unit: item.unit,
                unitPrice: item.unitPrice,
                priceSource: item.priceSource,
                confidence: item.confidence,
                position: index
            )
        }
        if !lineItems.isEmpty {
            try await client.from("quote_line_items").insert(lineItems).execute()
        }

        try await client.from("transcripts").insert(
            TranscriptInsert(quoteId: quoteID, text: transcript, sttSource: "on_device", status: "done")
        ).execute()
        cacheTranscript(transcript, quoteId: quoteID)

        return quoteID
    }

    /// Duplicate a quote as a new draft (title, summary, notes, amounts, currency
    /// and all line items are copied; the copy is never pinned). Returns the new id.
    @discardableResult
    static func duplicateQuote(id: UUID) async throws -> UUID {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }

        // Read the source quote's copyable fields.
        struct SourceQuote: Decodable {
            let title: String?
            let jobSummary: String?
            let scope: [String]?
            let notes: String?
            let subtotal: Double?
            let total: Double
            let currency: String?
            /// Carried over so the copy is taxed like its original — the database
            /// recomputes tax_amount and total from it, so leaving it out would
            /// quietly produce a tax-free duplicate.
            let taxRate: Double?
            enum CodingKeys: String, CodingKey {
                case title
                case jobSummary = "job_summary"
                case scope, notes, subtotal, total, currency
                case taxRate = "tax_rate"
            }
        }
        let source: SourceQuote = try await client
            .from("quotes")
            .select("title, job_summary, scope, notes, subtotal, total, currency, tax_rate")
            .eq("id", value: id)
            .single()
            .execute()
            .value

        struct DuplicateInsert: Encodable {
            let userId: UUID
            let title: String?
            let jobSummary: String?
            let scope: [String]
            let notes: String?
            let subtotal: Double?
            let total: Double
            let status: String
            let currency: String?
            let taxRate: Double
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case title
                case jobSummary = "job_summary"
                case scope, notes, subtotal, total, status, currency
                case taxRate = "tax_rate"
            }
        }
        let copiedTitle = source.title.map { $0.isEmpty ? $0 : "\($0) (copy)" }
        let inserted: InsertedRow = try await client
            .from("quotes")
            .insert(DuplicateInsert(
                userId: userID,
                title: copiedTitle,
                jobSummary: source.jobSummary,
                scope: source.scope ?? [],
                notes: source.notes,
                subtotal: source.subtotal,
                total: source.total,
                status: "draft",
                currency: source.currency,
                taxRate: source.taxRate ?? 0
            ), returning: .representation)
            .select("id")
            .single()
            .execute()
            .value
        let newID = inserted.id

        // Copy the line items over, preserving order.
        let items = try await fetchLineItems(quoteId: id)
        let copies = items.map { item in
            LineItemInsert(
                quoteId: newID,
                description: item.description ?? "",
                type: item.type,
                quantity: item.quantity,
                unit: item.unit,
                unitPrice: item.unitPrice,
                priceSource: item.priceSource,
                confidence: item.confidence,
                position: item.position
            )
        }
        if !copies.isEmpty {
            try await client.from("quote_line_items").insert(copies).execute()
        }

        // Copy the transcript so the duplicate keeps "View transcript" and can be
        // regenerated, just like the original.
        if let transcript = try? await fetchTranscript(quoteId: id) ?? cachedTranscript(quoteId: id) {
            try await client.from("transcripts").insert(
                TranscriptInsert(quoteId: newID, text: transcript, sttSource: "on_device", status: "done")
            ).execute()
            cacheTranscript(transcript, quoteId: newID)
        }

        return newID
    }

    /// Delete a quote (line items and transcript cascade via FK).
    static func deleteQuote(id: UUID) async throws {
        try await client.from("quotes").delete().eq("id", value: id).execute()
        // The server's cascade doesn't reach this phone. Left alone, the items
        // and the transcript of a deleted quote stay readable on disk.
        if let userID = client.auth.currentUser?.id {
            LocalCache.clear(quoteID: id, userID: userID)
        }
    }

    /// Pin or unpin a quote (pinned quotes surface in a section at the top).
    static func setPinned(id: UUID, pinned: Bool) async throws {
        try await client
            .from("quotes")
            .update(["pinned": pinned])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Editing

    /// Rename a quote, and nothing else. `updateQuoteCore` would do it, but it
    /// writes the scope and both totals alongside — figures this caller has no
    /// business restating just to change a name.
    static func setTitle(quoteId: UUID, title: String) async throws {
        struct Payload: Encodable { let title: String }
        try await client
            .from("quotes")
            .update(Payload(title: title))
            .eq("id", value: quoteId)
            .execute()
    }

    /// Update the written parts of a quote. Deliberately no money in it: the
    /// figures belong to the line items, and a payload that carried them would
    /// have to restate them correctly every time a sentence was edited.
    static func updateQuoteText(id: UUID, title: String?, jobSummary: String?,
                                scope: [String]) async throws {
        struct Payload: Encodable {
            let title: String?
            let jobSummary: String?
            let scope: [String]
            enum CodingKeys: String, CodingKey {
                case title
                case jobSummary = "job_summary"
                case scope
            }
        }
        try await client
            .from("quotes")
            .update(Payload(title: title, jobSummary: jobSummary, scope: scope))
            .eq("id", value: id)
            .execute()
    }

    static func updateStatus(id: UUID, status: String) async throws {
        try await client
            .from("quotes")
            .update(["status": status])
            .eq("id", value: id)
            .execute()
    }

    /// Move a quote's validity date. Sent as "yyyy-MM-dd" because the column is
    /// a Postgres `date`, not a timestamp — the same format it comes back in.
    static func updateValidityDate(id: UUID, date: Date) async throws {
        struct Payload: Encodable {
            let validityDate: String
            enum CodingKeys: String, CodingKey { case validityDate = "validity_date" }
        }
        try await client
            .from("quotes")
            .update(Payload(validityDate: QuoteDateFormat.dayOnly.string(from: date)))
            .eq("id", value: id)
            .execute()
    }

    /// Rename a quote. Used when a draft's title is edited after the draft was
    /// already banked at generation time.
    static func updateTitle(id: UUID, title: String?) async throws {
        struct Payload: Encodable { let title: String? }
        try await client
            .from("quotes")
            .update(Payload(title: title))
            .eq("id", value: id)
            .execute()
    }

    /// Change a quote's currency (a relabel — the stored amounts are unchanged).
    static func updateCurrency(id: UUID, currency: String) async throws {
        try await client
            .from("quotes")
            .update(["currency": currency])
            .eq("id", value: id)
            .execute()
    }

    /// Persist a converted quote: new currency plus the recomputed subtotal.
    /// `tax_amount` and `total` are derived from the subtotal by a database
    /// trigger, so sending them here would only be overwritten.
    static func updateCurrencyAndSubtotal(id: UUID, currency: String, subtotal: Double) async throws {
        struct Payload: Encodable { let currency: String; let subtotal: Double }
        try await client
            .from("quotes")
            .update(Payload(currency: currency, subtotal: subtotal))
            .eq("id", value: id)
            .execute()
    }

    /// Update a quote's status (draft / sent / viewed / accepted / declined / expired).
    /// A link the customer can open, minted on first use and stable after that.
    ///
    /// Sharing the same quote twice hands out the same address, so a link
    /// already sitting in someone's messages keeps working — and the token is
    /// only ever created for quotes that actually get shared.
    static func shareLink(quoteId: UUID) async throws -> URL {
        struct Params: Encodable { let quote_id: UUID }
        let token: String = try await client
            .rpc("ensure_share_token", params: Params(quote_id: quoteId))
            .execute()
            .value
        guard let url = AppInfo.shareURL(token: token) else {
            throw URLError(.badURL)
        }
        return url
    }

    /// Quotes made since `date`, for the free tier's daily allowance.
    ///
    /// Counted from `quote_usage` rather than `quotes`: the ledger records that
    /// a quote was made, so deleting one doesn't hand its allowance back. RLS
    /// scopes the count to the signed-in user, and there is no delete policy on
    /// that table for anyone.
    static func quotesUsed(since date: Date) async throws -> Int {
        let response = try await client
            .from("quote_usage")
            .select("id", head: true, count: .exact)
            .gte("created_at", value: QuoteDateFormat.timestamp.string(from: date))
            .execute()
        return response.count ?? 0
    }
}

private struct QuoteInsert: Encodable {
    let userId: UUID
    let title: String?
    let jobSummary: String
    let scope: [String]
    let notes: String?
    let subtotal: Double
    /// Percentage taken from the business profile. `tax_amount` and `total` are
    /// derived from this and `subtotal` by a database trigger, as are `number`
    /// and `validity_date`, so none of them are sent.
    let taxRate: Double
    let status: String
    let currency: String
    /// Nil when the user didn't name a client.
    let customerId: UUID?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case title
        case jobSummary = "job_summary"
        case scope, notes, subtotal, status, currency
        case taxRate = "tax_rate"
        case customerId = "customer_id"
    }
}

private struct LineItemInsert: Encodable {
    let quoteId: UUID
    let description: String
    let type: String
    let quantity: Double?
    let unit: String?
    let unitPrice: Double?
    let priceSource: String?
    let confidence: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case quoteId = "quote_id"
        case description, type, quantity, unit
        case unitPrice = "unit_price"
        case priceSource = "price_source"
        case confidence, position
    }
}

private struct TranscriptInsert: Encodable {
    let quoteId: UUID
    let text: String
    let sttSource: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case quoteId = "quote_id"
        case text
        case sttSource = "stt_source"
        case status
    }
}

private struct InsertedRow: Decodable {
    let id: UUID
}
