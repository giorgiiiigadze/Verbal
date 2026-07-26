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

enum QuoteService {
    private static var client: SupabaseClient { SupabaseManager.client }

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

    /// Extract a structured quote from `transcript` and save it. Returns the new quote id.
    @discardableResult
    static func createQuote(transcript: String, title: String) async throws -> UUID {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }

        // 1. AI extraction (server-side; never exposes the OpenAI key).
        let extraction: ExtractResponse = try await client.functions.invoke(
            "extract-quote",
            options: FunctionInvokeOptions(body: ExtractRequest(transcript: transcript))
        )
        let quote = extraction.quote

        // 2. Deterministic totals (never trust the LLM for math).
        let subtotal = quote.lineItems.reduce(into: 0.0) { sum, item in
            if let qty = item.quantity, let price = item.unitPrice {
                sum += qty * price
            }
        }

        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteInsert = QuoteInsert(
            userId: userID,
            title: resolvedTitle.isEmpty ? nil : resolvedTitle,
            jobSummary: quote.jobSummary,
            notes: quote.notes,
            subtotal: subtotal,
            total: subtotal,
            status: "draft"
        )

        // 3. Persist the quote and get its id.
        let inserted: InsertedRow = try await client
            .from("quotes")
            .insert(quoteInsert, returning: .representation)
            .select("id")
            .single()
            .execute()
            .value
        let quoteID = inserted.id

        // 4. Persist line items (preserving order) and the transcript.
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
}

private struct ExtractResponse: Decodable {
    let quote: ExtractedQuote
}

private struct ExtractedQuote: Decodable {
    let jobSummary: String
    let notes: String?
    let lineItems: [ExtractedLineItem]

    enum CodingKeys: String, CodingKey {
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
