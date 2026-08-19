//
//  QuoteService.swift
//  Verbal
//
//  Turns a transcript into a saved quote: calls the extract-quote Edge Function
//  (AI structured extraction), computes totals in code, and persists the quote,
//  its line items, and the transcript to Supabase.
//
//  The domain types this service reads and writes live in Models/ —
//  QuoteSummary, QuoteLineItem, GeneratedQuote, RateCardItem and friends. What
//  stays here is the network surface: the service itself and the private
//  request/insert payloads that only it ever encodes.
//

import Foundation
import Supabase

enum QuoteService {
    private static var client: SupabaseClient { SupabaseManager.client }

    /// Fetch a quote's line items, in order.
    static func fetchLineItems(quoteId: UUID) async throws -> [QuoteLineItem] {
        let response: PostgrestResponse<[QuoteLineItem]> = try await client
            .from("quote_line_items")
            .select("id, description, type, quantity, unit, unit_price, price_source, confidence, position")
            .eq("quote_id", value: quoteId)
            .order("position", ascending: true)
            .execute()
        // Cached so a quote opened offline shows its work rather than an empty
        // table — the list surviving without its contents is half a feature.
        if let userID = client.auth.currentUser?.id {
            LocalCache.save(response.data, for: .lineItems(quoteID: quoteId), userID: userID)
        }
        return response.value
    }

    /// Fetch the transcript text saved with a quote.
    static func fetchTranscript(quoteId: UUID) async throws -> String? {
        struct Row: Decodable { let text: String? }
        let rows: [Row] = try await client
            .from("transcripts")
            .select("text")
            .eq("quote_id", value: quoteId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        let text = rows.first?.text
        if let text { cacheTranscript(text, quoteId: quoteId) }
        return text
    }

    /// The transcript as it was last seen, for when the network can't be
    /// reached. Read straight from disk rather than held in memory: it is
    /// wanted only when the sheet is opened, and some of these are long.
    static func cachedTranscript(quoteId: UUID) -> String? {
        guard let userID = client.auth.currentUser?.id else { return nil }
        return LocalCache.load(String.self, for: .transcript(quoteID: quoteId), userID: userID)
    }

    /// Store the transcripts of every quote that hasn't got one on disk yet, in
    /// a single request. Caching on create covers quotes made from here on, and
    /// caching on open covers whatever the user happens to visit — neither
    /// reaches the quotes already on the account, which offline showed "No
    /// transcript saved." for work the user had dictated themselves. Run at
    /// launch, so going offline later finds the whole list readable.
    static func cacheMissingTranscripts(for quoteIDs: [UUID]) async {
        guard let userID = client.auth.currentUser?.id else { return }
        let missing = quoteIDs.filter {
            !LocalCache.exists(for: .transcript(quoteID: $0), userID: userID)
        }
        guard !missing.isEmpty else { return }

        struct Row: Decodable {
            let quoteId: UUID
            let text: String?
            enum CodingKeys: String, CodingKey {
                case quoteId = "quote_id"
                case text
            }
        }
        guard let rows: [Row] = try? await client
            .from("transcripts")
            .select("quote_id, text")
            .in("quote_id", values: missing)
            .order("created_at", ascending: true)
            .execute()
            .value
        else { return }

        // Oldest first, so where a quote carries more than one transcript the
        // newest is what's left standing — the same one a single fetch picks.
        var newest: [UUID: String] = [:]
        for row in rows {
            if let text = row.text, !text.isEmpty { newest[row.quoteId] = text }
        }
        for (quoteID, text) in newest {
            cacheTranscript(text, quoteId: quoteID)
        }
    }

    /// Keep a copy of the words a quote was built from. Called both when one is
    /// fetched and when one is first recorded — the second is what matters, as
    /// it means a quote dictated in a basement can be reread there without the
    /// user ever having opened it somewhere with signal.
    private static func cacheTranscript(_ text: String, quoteId: UUID) {
        guard let userID = client.auth.currentUser?.id,
              let data = try? JSONEncoder().encode(text) else { return }
        LocalCache.save(data, for: .transcript(quoteID: quoteId), userID: userID)
    }

    // MARK: - Customers

    /// Escapes the characters `ILIKE` treats as wildcards, so a client name is
    /// matched literally. Without this, a name holding `%`, `_` or `*` (which
    /// PostgREST rewrites to `%`) matches some unrelated customer and the quote
    /// is silently filed under the wrong person.
    private static func escapingLikeWildcards(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "%" || character == "_" || character == "*" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// Resolve a typed client name to a customer row, reusing an existing one
    /// with the same name (case-insensitive) so repeat customers don't pile up
    /// as duplicates. Returns nil for an empty name.
    static func customerID(named name: String, userID: UUID) async throws -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        struct Row: Decodable { let id: UUID }
        let existing: [Row] = try await client
            .from("customers")
            .select("id")
            .eq("user_id", value: userID)
            .ilike("name", pattern: escapingLikeWildcards(trimmed))
            .limit(1)
            .execute()
            .value
        if let found = existing.first { return found.id }

        struct CustomerInsert: Encodable {
            let userId: UUID
            let name: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case name
            }
        }
        let created: Row = try await client
            .from("customers")
            .insert(CustomerInsert(userId: userID, name: trimmed), returning: .representation)
            .select("id")
            .single()
            .execute()
            .value
        return created.id
    }

    /// Names the user has quoted for before — powers suggestions on the client field.
    static func customerNames() async throws -> [String] {
        guard let userID = client.auth.currentUser?.id else { return [] }
        struct Row: Decodable { let name: String? }
        let rows: [Row] = try await client
            .from("customers")
            .select("name")
            .eq("user_id", value: userID)
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value
        return rows.compactMap(\.name).filter { !$0.isEmpty }
    }

    /// Rename a client on every quote of theirs at once, merging them into an
    /// existing person when the new name is already taken.
    ///
    /// The name a client is filed under is whatever was said into the mic, and
    /// a misheard one could only be corrected quote by quote — which is also
    /// how "Tamar Beridze" and "Tamar Beridge" became two clients. So the merge
    /// isn't a separate feature: repointing the quotes and dropping the emptied
    /// row is what renaming onto an existing name has to mean.
    ///
    /// A change of spelling or capitalisation alone is not a merge — that is
    /// the same row being corrected, so the survivor is looked for among rows
    /// other than the ones being renamed.
    static func renameClient(from oldName: String, to newName: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let old = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty else { return }

        struct Row: Decodable { let id: UUID }
        struct NamePayload: Encodable { let name: String }
        struct CustomerPayload: Encodable {
            let customerId: UUID
            enum CodingKeys: String, CodingKey { case customerId = "customer_id" }
        }

        func rows(named name: String) async throws -> [Row] {
            try await client
                .from("customers")
                .select("id")
                .eq("user_id", value: userID)
                .ilike("name", pattern: escapingLikeWildcards(name))
                .execute()
                .value
        }

        let renaming = try await rows(named: old).map(\.id)
        guard !renaming.isEmpty else { return }
        let survivor = try await rows(named: new).map(\.id).first { !renaming.contains($0) }

        if let survivor {
            // Every quote of theirs moves to the person who keeps the name,
            // before the emptied rows go — an order that leaves no quote
            // pointing at a customer that no longer exists, even if the second
            // call never happens.
            try await client
                .from("quotes")
                .update(CustomerPayload(customerId: survivor))
                .eq("user_id", value: userID)
                .in("customer_id", values: renaming)
                .execute()
            // The survivor takes the spelling that was just typed, so correcting
            // the capitalisation of a name that already exists still corrects it.
            try await client
                .from("customers")
                .update(NamePayload(name: new))
                .eq("user_id", value: userID)
                .eq("id", value: survivor)
                .execute()
            try await client
                .from("customers")
                .delete()
                .eq("user_id", value: userID)
                .in("id", values: renaming)
                .execute()
        } else {
            try await client
                .from("customers")
                .update(NamePayload(name: new))
                .eq("user_id", value: userID)
                .in("id", values: renaming)
                .execute()
        }
    }

    /// Link an existing quote to a client by name (used when editing).
    static func setClient(quoteId: UUID, name: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let customerId = try await customerID(named: name, userID: userID)
        struct Payload: Encodable {
            let customerId: UUID?
            enum CodingKeys: String, CodingKey { case customerId = "customer_id" }
        }
        try await client
            .from("quotes")
            .update(Payload(customerId: customerId))
            .eq("id", value: quoteId)
            .execute()
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

    /// Overwrite a line item's editable fields (quote_id is left untouched).
    static func updateLineItem(id: UUID, description: String?, type: String, quantity: Double?,
                               unit: String?, unitPrice: Double?, priceSource: String,
                               position: Int) async throws {
        try await client
            .from("quote_line_items")
            .update(LineItemFields(description: description, type: type, quantity: quantity,
                                   unit: unit, unitPrice: unitPrice, priceSource: priceSource,
                                   position: position))
            .eq("id", value: id)
            .execute()
    }

    /// Insert a new line item into a quote.
    static func insertLineItem(quoteId: UUID, description: String?, type: String, quantity: Double?,
                               unit: String?, unitPrice: Double?, priceSource: String,
                               position: Int) async throws {
        struct Insert: Encodable {
            let quoteId: UUID
            let fields: LineItemFields
            // Flatten quote_id alongside the shared editable fields.
            enum CodingKeys: String, CodingKey { case quoteId = "quote_id" }
            func encode(to encoder: Encoder) throws {
                try fields.encode(to: encoder)
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(quoteId, forKey: .quoteId)
            }
        }
        try await client
            .from("quote_line_items")
            .insert(Insert(quoteId: quoteId,
                           fields: LineItemFields(description: description, type: type,
                                                  quantity: quantity, unit: unit,
                                                  unitPrice: unitPrice, priceSource: priceSource,
                                                  position: position)))
            .execute()
    }

    /// Fill in a price on a draft that was already banked, addressed by the
    /// line's position. Line items are inserted in order, so position finds
    /// them without the review screen having to carry server ids around.
    /// Quantity goes along because an unpriced line often has none, and a unit
    /// price with no quantity still totals nothing.
    static func setLineItemPrice(quoteId: UUID, position: Int,
                                 quantity: Double, unitPrice: Double) async throws {
        struct Payload: Encodable {
            let quantity: Double
            let unitPrice: Double
            let priceSource: String
            enum CodingKeys: String, CodingKey {
                case quantity
                case unitPrice = "unit_price"
                case priceSource = "price_source"
            }
        }
        try await client
            .from("quote_line_items")
            .update(Payload(quantity: quantity, unitPrice: unitPrice, priceSource: "rate_card"))
            .eq("quote_id", value: quoteId)
            .eq("position", value: position)
            .execute()
    }

    /// Recompute a quote's subtotal after its line items changed. `tax_amount`
    /// and `total` are derived from it by a database trigger.
    static func updateSubtotal(id: UUID, subtotal: Double) async throws {
        struct Payload: Encodable { let subtotal: Double }
        try await client
            .from("quotes")
            .update(Payload(subtotal: subtotal))
            .eq("id", value: id)
            .execute()
    }

    /// Delete a single line item.
    static func deleteLineItem(id: UUID) async throws {
        try await client.from("quote_line_items").delete().eq("id", value: id).execute()
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

    /// Update a single line item's unit price (used when converting a quote).
    static func updateLineItemPrice(id: UUID, unitPrice: Double) async throws {
        try await client
            .from("quote_line_items")
            .update(["unit_price": unitPrice])
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

    /// Run the AI extraction on a transcript, returning the structured quote (not persisted).
    /// Passes the user's active rate card so the AI can price known items.
    /// `tradeContext` is passed in rather than fetched: the caller already
    /// holds the preloaded profile, and a round trip here would sit on the
    /// critical path of the one moment the user is watching a spinner.
    static func generate(transcript: String, tradeContext: String?) async throws -> GeneratedQuote {
        let rateCard = (try? await fetchRateCard(activeOnly: true)) ?? []
        let request = ExtractRequest(
            transcript: transcript,
            rate_card: rateCard.map {
                RateCardPayload(name: $0.name, unit: $0.unit, unit_price: $0.unitPrice, type: $0.type)
            },
            currency: AppCurrency.current.rawValue,
            trade_context: tradeContext
        )
        let extraction: ExtractResponse = try await client.functions.invoke(
            "extract-quote",
            options: FunctionInvokeOptions(body: request)
        )
        let q = extraction.quote
        return GeneratedQuote(
            title: q.title,
            jobSummary: q.jobSummary,
            scope: q.scope,
            notes: q.notes,
            lineItems: q.lineItems.map {
                GeneratedLineItem(
                    description: $0.description,
                    type: $0.type,
                    quantity: $0.quantity,
                    unit: $0.unit,
                    unitPrice: $0.unitPrice,
                    priceSource: $0.priceSource,
                    confidence: $0.confidence
                )
            },
            clientName: q.customer?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
            flags: q.flags ?? []
        )
    }

    // MARK: - Rate card

    static func fetchRateCard(activeOnly: Bool = false) async throws -> [RateCardItem] {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let query = client
            .from("rate_card_items")
            .select("id, name, unit, unit_price, type, active")
            .eq("user_id", value: userID)
        let filtered = activeOnly ? query.eq("active", value: true) : query
        let response: PostgrestResponse<[RateCardItem]> = try await filtered
            .order("name", ascending: true)
            .execute()
        // Only the full card is cached; the active-only variant is a subset and
        // would overwrite it with less than the Rate Card tab needs to show.
        if !activeOnly {
            LocalCache.save(response.data, for: .rateCard, userID: userID)
        }
        return response.value
    }

    static func addRateCardItem(name: String, unit: String?, unitPrice: Double?, type: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        try await client.from("rate_card_items").insert(
            RateCardInsert(user_id: userID, name: name, unit: unit, unit_price: unitPrice, type: type, active: true)
        ).execute()
    }

    /// Rewrite a saved rate. Until this existed a price could only be corrected
    /// by deleting the rate and retyping it, which is how the card ended up
    /// holding the same job twice at different prices.
    static func updateRateCardItem(id: UUID, name: String, unit: String?,
                                   unitPrice: Double?, type: String) async throws {
        struct Payload: Encodable {
            let name: String
            let unit: String?
            let unitPrice: Double?
            let type: String
            enum CodingKeys: String, CodingKey {
                case name, unit, type
                case unitPrice = "unit_price"
            }
        }
        try await client
            .from("rate_card_items")
            .update(Payload(name: name, unit: unit, unitPrice: unitPrice, type: type))
            .eq("id", value: id)
            .execute()
    }

    /// Update one saved rate's price. Used when the user changes their main
    /// currency and chooses to reprice the rate card rather than relabel it.
    static func updateRateCardPrice(id: UUID, unitPrice: Double) async throws {
        try await client
            .from("rate_card_items")
            .update(["unit_price": unitPrice])
            .eq("id", value: id)
            .execute()
    }

    /// Priced lines from recent quotes that the rate card doesn't hold yet.
    ///
    /// A spoken price that worked once will work again, but only if it's saved —
    /// otherwise the same job gets priced from memory every time. This is the
    /// offer `SaveRatesSheet` makes at the end of a recording, made again later
    /// for the ones that got away.
    ///
    /// `price_source` of `spoken` is the point: a line priced from the rate card
    /// is already saved by definition, and a `missing` one has no price to save.
    static func rateCandidates(notIn existing: [RateCardItem],
                               limit: Int = 80) async throws -> [RateCandidate] {
        try await recentSpokenPrices(limit: limit).filter { candidate in
            !existing.contains { $0.looksLike(candidate.name) }
        }
    }

    /// The same lines, before they're measured against the rate card.
    ///
    /// Split out so the fetch can run alongside the rate card during bootstrap
    /// instead of queueing behind it — the comparison is cheap and local, and
    /// waiting for one list to arrive before asking for the other is what would
    /// make the offer show up late.
    static func recentSpokenPrices(limit: Int = 80) async throws -> [RateCandidate] {
        struct Row: Decodable {
            let description: String?
            let unit: String?
            let unitPrice: Double?
            let type: String

            enum CodingKeys: String, CodingKey {
                case description, unit, type
                case unitPrice = "unit_price"
            }
        }

        let response: PostgrestResponse<[Row]> = try await client
            .from("quote_line_items")
            .select("description, unit, unit_price, type")
            .eq("price_source", value: "spoken")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        var seen = Set<String>()
        var candidates: [RateCandidate] = []
        for row in response.value {
            guard let name = row.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                  name.count >= 3,
                  let price = row.unitPrice, price > 0
            else { continue }
            // The same job quoted three times is one thing to offer, and the
            // newest wording of it is the one the user last chose.
            guard seen.insert(name.lowercased()).inserted else { continue }
            candidates.append(RateCandidate(name: name, unit: row.unit,
                                            unitPrice: price, type: row.type))
        }
        return candidates
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

    static func deleteRateCardItem(id: UUID) async throws {
        try await client.from("rate_card_items").delete().eq("id", value: id).execute()
    }

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

    /// Pin or unpin a quote (pinned quotes surface in a section at the top).
    static func setPinned(id: UUID, pinned: Bool) async throws {
        try await client
            .from("quotes")
            .update(["pinned": pinned])
            .eq("id", value: id)
            .execute()
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
}

enum QuoteError: LocalizedError {
    case notSignedIn
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in to save a quote."
        }
    }
}

// MARK: - Edge function I/O

private struct ExtractRequest: Encodable {
    let transcript: String
    let rate_card: [RateCardPayload]
    let currency: String
    /// The user's trade. The prompt has had a slot for this since it was
    /// written and nothing ever filled it — "eight of the 20 mil" is cable to
    /// an electrician and pipe to a plumber, and the model was guessing.
    let trade_context: String?
}

private struct RateCardPayload: Encodable {
    let name: String
    let unit: String?
    let unit_price: Double?
    let type: String
}

private struct ExtractResponse: Decodable {
    let quote: ExtractedQuote
}

private struct ExtractedQuote: Decodable {
    let title: String
    let jobSummary: String
    let scope: [String]
    let notes: String?
    let lineItems: [ExtractedLineItem]
    /// Both are required by the schema, so the model always sends them — but
    /// their contents are nullable and older responses predate them, so neither
    /// is worth failing a whole extraction over.
    let customer: ExtractedCustomer?
    let flags: [String]?

    enum CodingKeys: String, CodingKey {
        case title
        case jobSummary = "job_summary"
        case scope, notes, customer, flags
        case lineItems = "line_items"
    }
}

private struct ExtractedCustomer: Decodable {
    let name: String?
    let address: String?
}

private struct ExtractedLineItem: Decodable {
    let description: String
    let type: String
    let quantity: Double?
    let unit: String?
    let unitPrice: Double?
    let priceSource: String?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case description, type, quantity, unit
        case unitPrice = "unit_price"
        case priceSource = "price_source"
        case confidence
    }
}

// MARK: - Insert payloads

private struct RateCardInsert: Encodable {
    let user_id: UUID
    let name: String
    let unit: String?
    let unit_price: Double?
    let type: String
    let active: Bool
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

/// The editable columns of a line item (no quote_id), shared by update & insert.
private struct LineItemFields: Encodable {
    let description: String?
    let type: String
    let quantity: Double?
    let unit: String?
    let unitPrice: Double?
    let priceSource: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case description, type, quantity, unit
        case unitPrice = "unit_price"
        case priceSource = "price_source"
        case position, confidence
    }

    /// Written by hand so every column is sent, nil included.
    ///
    /// A synthesised encoder leaves a nil optional out of the JSON entirely,
    /// and an absent column in a PATCH tells PostgREST to leave that column
    /// as it is. So clearing a price sent `price_source: "missing"` and kept
    /// the old `unit_price` beside it — the row disagreed with itself, and the
    /// price the user had just deleted was still there the next time they
    /// opened the editor.
    ///
    /// `confidence` is always null. It is the model's read on a line it heard
    /// spoken, and once the user has typed over that line there is nothing
    /// left for the read to be about — a price someone has just corrected by
    /// hand should not still be telling them it is worth checking. The same
    /// applies to a line inserted here, which the model never saw at all.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unit, forKey: .unit)
        try container.encode(unitPrice, forKey: .unitPrice)
        try container.encode(priceSource, forKey: .priceSource)
        try container.encode(position, forKey: .position)
        try container.encodeNil(forKey: .confidence)
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
