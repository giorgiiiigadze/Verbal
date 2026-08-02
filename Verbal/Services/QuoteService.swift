//
//  QuoteService.swift
//  Verbal
//
//  Turns a transcript into a saved quote: calls the extract-quote Edge Function
//  (AI structured extraction), computes totals in code, and persists the quote,
//  its line items, and the transcript to Supabase.
//

import Foundation
import Supabase

/// Lightweight quote row for the Home list.
struct QuoteSummary: Identifiable, Decodable, Sendable {
    let id: UUID
    let title: String?
    let jobSummary: String?
    let total: Double
    /// Mutable so Home can optimistically reflect a status change from the menu.
    var status: String
    let createdAt: Date
    /// ISO 4217 code this quote was priced in. Nil on legacy rows; formatting
    /// falls back to the user's current setting in that case.
    let currency: String?
    /// Pinned quotes sort into a dedicated section at the top of the Home list.
    /// Mutable so Home can optimistically reflect a pin toggle.
    var pinned: Bool
    /// Client-facing "what we'll do" bullet list (may be empty on legacy rows).
    var scope: [String]

    /// Sequential per-user reference, e.g. "0007". Assigned by a database
    /// trigger on insert, so it's always present on new rows.
    let number: String?
    /// Date the quote stops being valid, as stored ("yyyy-MM-dd"). Kept as text
    /// because Postgres `date` columns aren't ISO-8601 timestamps.
    let validityDateText: String?
    /// Name of the customer this quote is for, via the linked customer row.
    let clientName: String?
    /// Sum of the line items, before tax.
    let subtotal: Double
    /// Tax percentage (20 = 20%) and the resulting amount. Both are computed
    /// by the database from `subtotal`, so they always agree with `total`.
    let taxRate: Double
    let taxAmount: Double

    enum CodingKeys: String, CodingKey {
        case id, title
        case jobSummary = "job_summary"
        case total, status
        case createdAt = "created_at"
        case currency, pinned, scope, number, subtotal
        case taxRate = "tax_rate"
        case taxAmount = "tax_amount"
        case validityDate = "validity_date"
        case customers
    }

    /// Shape of the embedded `customers(name)` relation.
    private struct CustomerRef: Decodable { let name: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        jobSummary = try c.decodeIfPresent(String.self, forKey: .jobSummary)
        total = try c.decode(Double.self, forKey: .total)
        status = try c.decode(String.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        scope = try c.decodeIfPresent([String].self, forKey: .scope) ?? []
        number = try c.decodeIfPresent(String.self, forKey: .number)
        validityDateText = try c.decodeIfPresent(String.self, forKey: .validityDate)
        clientName = try c.decodeIfPresent(CustomerRef.self, forKey: .customers)?.name
        // Legacy rows predate the tax columns being selected; fall back to a
        // tax-free quote rather than failing to decode the whole list.
        subtotal = try c.decodeIfPresent(Double.self, forKey: .subtotal) ?? total
        taxRate = try c.decodeIfPresent(Double.self, forKey: .taxRate) ?? 0
        taxAmount = try c.decodeIfPresent(Double.self, forKey: .taxAmount) ?? 0
    }

    /// True when a tax line should appear on the quote and its PDF.
    var hasTax: Bool { taxRate > 0 && taxAmount > 0 }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let jobSummary, !jobSummary.isEmpty { return jobSummary }
        return "Untitled quote"
    }

    /// "Quote 0007" — the reference shown to the user and printed on the PDF.
    var numberLabel: String? {
        guard let number, !number.isEmpty else { return nil }
        return "Quote \(number)"
    }

    var validityDate: Date? {
        guard let validityDateText else { return nil }
        return QuoteDateFormat.dayOnly.date(from: validityDateText)
    }

    /// True once the validity date has passed (status is left alone; this is
    /// purely how the date reads to the user).
    var isPastValidity: Bool {
        guard let validityDate else { return false }
        return validityDate < Calendar.current.startOfDay(for: Date())
    }
}

extension Double {
    /// Money rounded to two decimals, matching the database's `round(x, 2)`.
    var roundedToCents: Double { (self * 100).rounded() / 100 }
}

/// Formatters for Postgres `date` values, which arrive as "yyyy-MM-dd".
enum QuoteDateFormat {
    static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Medium, localized rendering for display — e.g. "14 Aug 2026".
    static func display(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// A line item shown on the quote detail table.
struct QuoteLineItem: Identifiable, Decodable, Sendable {
    let id: UUID
    let description: String?
    let type: String
    let quantity: Double?
    let unit: String?
    let unitPrice: Double?
    let priceSource: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, description, type, quantity, unit
        case unitPrice = "unit_price"
        case priceSource = "price_source"
        case position
    }

    var isMissingPrice: Bool { priceSource == "missing" || unitPrice == nil }

    var lineTotal: Double? {
        guard let quantity, let unitPrice else { return nil }
        return quantity * unitPrice
    }

    var quantityText: String? { quantityLabel(quantity, unit) }
}

enum QuoteService {
    private static var client: SupabaseClient { SupabaseManager.client }

    /// Fetch a quote's line items, in order.
    static func fetchLineItems(quoteId: UUID) async throws -> [QuoteLineItem] {
        try await client
            .from("quote_line_items")
            .select("id, description, type, quantity, unit, unit_price, price_source, position")
            .eq("quote_id", value: quoteId)
            .order("position", ascending: true)
            .execute()
            .value
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
        return rows.first?.text
    }

    // MARK: - Customers

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
            .ilike("name", pattern: trimmed)
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
    }

    // MARK: - Editing

    /// Update a quote's core editable fields plus recomputed totals.
    static func updateQuoteCore(id: UUID, title: String?, jobSummary: String?,
                                scope: [String], subtotal: Double, total: Double) async throws {
        struct Payload: Encodable {
            let title: String?
            let jobSummary: String?
            let scope: [String]
            let subtotal: Double
            let total: Double
            enum CodingKeys: String, CodingKey {
                case title
                case jobSummary = "job_summary"
                case scope, subtotal, total
            }
        }
        try await client
            .from("quotes")
            .update(Payload(title: title, jobSummary: jobSummary, scope: scope,
                            subtotal: subtotal, total: total))
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

    /// Delete a single line item.
    static func deleteLineItem(id: UUID) async throws {
        try await client.from("quote_line_items").delete().eq("id", value: id).execute()
    }

    /// Update a quote's status (draft / sent / viewed / accepted / declined / expired).
    static func updateStatus(id: UUID, status: String) async throws {
        try await client
            .from("quotes")
            .update(["status": status])
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

    /// Persist a converted quote: new currency plus recomputed subtotal/total.
    static func updateCurrencyAndTotal(id: UUID, currency: String, total: Double) async throws {
        struct Payload: Encodable { let currency: String; let subtotal: Double; let total: Double }
        try await client
            .from("quotes")
            .update(Payload(currency: currency, subtotal: total, total: total))
            .eq("id", value: id)
            .execute()
    }

    /// Run the AI extraction on a transcript, returning the structured quote (not persisted).
    /// Passes the user's active rate card so the AI can price known items.
    static func generate(transcript: String) async throws -> GeneratedQuote {
        let rateCard = (try? await fetchRateCard(activeOnly: true)) ?? []
        let request = ExtractRequest(
            transcript: transcript,
            rate_card: rateCard.map {
                RateCardPayload(name: $0.name, unit: $0.unit, unit_price: $0.unitPrice, type: $0.type)
            },
            currency: AppCurrency.current.rawValue
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
                    priceSource: $0.priceSource
                )
            }
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
        return try await filtered.order("name", ascending: true).execute().value
    }

    static func addRateCardItem(name: String, unit: String?, unitPrice: Double?, type: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        try await client.from("rate_card_items").insert(
            RateCardInsert(user_id: userID, name: name, unit: unit, unit_price: unitPrice, type: type, active: true)
        ).execute()
    }

    static func deleteRateCardItem(id: UUID) async throws {
        try await client.from("rate_card_items").delete().eq("id", value: id).execute()
    }

    /// Fetch the signed-in user's quotes, newest first.
    static func fetchQuotes() async throws -> [QuoteSummary] {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        return try await client
            .from("quotes")
            .select("id, title, job_summary, total, status, created_at, currency, pinned, scope, number, validity_date, subtotal, tax_rate, tax_amount, customers(name)")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value
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
            enum CodingKeys: String, CodingKey {
                case title
                case jobSummary = "job_summary"
                case scope, notes, subtotal, total, currency
            }
        }
        let source: SourceQuote = try await client
            .from("quotes")
            .select("title, job_summary, scope, notes, subtotal, total, currency")
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
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case title
                case jobSummary = "job_summary"
                case scope, notes, subtotal, total, status, currency
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
                currency: source.currency
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
                confidence: nil,
                position: item.position
            )
        }
        if !copies.isEmpty {
            try await client.from("quote_line_items").insert(copies).execute()
        }

        // Copy the transcript so the duplicate keeps "View transcript" and can be
        // regenerated, just like the original.
        if let transcript = try? await fetchTranscript(quoteId: id) {
            try await client.from("transcripts").insert(
                TranscriptInsert(quoteId: newID, text: transcript, sttSource: "on_device", status: "done")
            ).execute()
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
                confidence: nil,
                position: index
            )
        }
        if !lineItems.isEmpty {
            try await client.from("quote_line_items").insert(lineItems).execute()
        }

        try await client.from("transcripts").insert(
            TranscriptInsert(quoteId: quoteID, text: transcript, sttSource: "on_device", status: "done")
        ).execute()

        return quoteID
    }
}

/// A structured quote produced by the AI, before it's persisted — used in the review UI.
struct GeneratedQuote: Sendable {
    var title: String
    var jobSummary: String
    var scope: [String]
    var notes: String?
    var lineItems: [GeneratedLineItem]
}

struct GeneratedLineItem: Identifiable, Sendable {
    let id = UUID()
    var description: String
    var type: String
    var quantity: Double?
    var unit: String?
    var unitPrice: Double?
    var priceSource: String?

    var isMissingPrice: Bool { priceSource == "missing" || unitPrice == nil }
    var lineTotal: Double? {
        guard let quantity, let unitPrice else { return nil }
        return quantity * unitPrice
    }
    var quantityText: String? { quantityLabel(quantity, unit) }
}

/// Formats a quote's timestamp as a compact date + time indicator, e.g.
/// "Just now", "4 minutes ago", "Today, 7:45 PM", "Yesterday, 7:45 PM", or "Jul 27".
func quoteDateLabel(_ date: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let seconds = now.timeIntervalSince(date)

    if seconds < 60 { return "Just now" }
    if seconds < 3600 {
        let minutes = Int(seconds / 60)
        return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }

    let time = date.formatted(.dateTime.hour().minute())
    if calendar.isDateInToday(date) { return "Today, \(time)" }
    if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

/// Formats a quantity + unit like "8 each" or "20 meters".
func quantityLabel(_ quantity: Double?, _ unit: String?) -> String? {
    guard let quantity else { return nil }
    let q = quantity.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(quantity))
        : String(format: "%.2f", quantity)
    return [q, unit].compactMap { $0 }.joined(separator: " ")
}

/// A saved rate-card entry (labor/material/other) used to auto-price quotes.
struct RateCardItem: Identifiable, Decodable, Sendable {
    let id: UUID
    let name: String
    let unit: String?
    let unitPrice: Double?
    let type: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, unit
        case unitPrice = "unit_price"
        case type, active
    }

    var priceText: String? {
        guard let unitPrice else { return nil }
        let amount = AppCurrency.format(unitPrice)
        return [amount, unit].compactMap { $0 }.joined(separator: " / ")
    }
}

private struct RateCardInsert: Encodable {
    let user_id: UUID
    let name: String
    let unit: String?
    let unit_price: Double?
    let type: String
    let active: Bool
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

    enum CodingKeys: String, CodingKey {
        case title
        case jobSummary = "job_summary"
        case scope, notes
        case lineItems = "line_items"
    }
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
        case position
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
