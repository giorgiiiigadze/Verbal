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
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case jobSummary = "job_summary"
        case total, status
        case createdAt = "created_at"
    }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let jobSummary, !jobSummary.isEmpty { return jobSummary }
        return "Untitled quote"
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

    /// Delete a quote (line items and transcript cascade via FK).
    static func deleteQuote(id: UUID) async throws {
        try await client.from("quotes").delete().eq("id", value: id).execute()
    }

    /// Update a quote's status (draft / sent / viewed / accepted / declined / expired).
    static func updateStatus(id: UUID, status: String) async throws {
        try await client
            .from("quotes")
            .update(["status": status])
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
            }
        )
        let extraction: ExtractResponse = try await client.functions.invoke(
            "extract-quote",
            options: FunctionInvokeOptions(body: request)
        )
        let q = extraction.quote
        return GeneratedQuote(
            title: q.title,
            jobSummary: q.jobSummary,
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
            .select("id, title, job_summary, total, status, created_at")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Persist an already-generated quote (from `generate`) with its transcript.
    @discardableResult
    static func save(_ quote: GeneratedQuote, transcript: String, title: String) async throws -> UUID {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }

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
            notes: quote.notes,
            subtotal: subtotal,
            total: subtotal,
            status: "draft"
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
        let amount = unitPrice.formatted(.number.precision(.fractionLength(2)))
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
    let notes: String?
    let lineItems: [ExtractedLineItem]

    enum CodingKeys: String, CodingKey {
        case title
        case jobSummary = "job_summary"
        case notes
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
    let notes: String?
    let subtotal: Double
    let total: Double
    let status: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case title
        case jobSummary = "job_summary"
        case notes, subtotal, total, status
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
