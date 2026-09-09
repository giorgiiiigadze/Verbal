//
//  QuoteService+Extraction.swift
//  Verbal
//
//  The one call that isn't a table: the transcript goes to the extract-quote
//  Edge Function and comes back as a quote. The shapes below are that
//  function's contract, which is why they live with the call and nowhere else.
//

import Foundation
import Supabase

extension QuoteService {
    /// Run the AI extraction on a transcript, returning the structured quote (not persisted).
    /// Passes the user's active rate card so the AI can price known items.
    /// `tradeContext` is passed in rather than fetched: the caller already
    /// holds the preloaded profile, and a round trip here would sit on the
    /// critical path of the one moment the user is watching a spinner.
    static func generate(transcript: String, tradeContext: String?,
                         rateCard: [RateCardItem], taxRate: Double?) async throws -> GeneratedQuote {
        // The recording screen starts these database reads before the accuracy
        // pass. Accepting their results here keeps them off the critical path
        // and avoids fetching the rate card a second time.
        let request = ExtractRequest(
            transcript: transcript,
            rate_card: rateCard.map {
                RateCardPayload(name: $0.name, unit: $0.unit, unit_price: $0.unitPrice, type: $0.type)
            },
            currency: AppCurrency.current.rawValue,
            trade_context: tradeContext,
            tax_rate: taxRate
        )
        // Measured, not guessed: extraction averages about nine seconds and the
        // slowest real call on record took twenty-four. Forty-five leaves room
        // for a bad day on a bad connection and still gives up long before
        // URLSession's own minute — by which point the user has decided the app
        // is broken and there is nothing left to salvage.
        let extraction: ExtractResponse
        do {
            extraction = try await withTimeout(.seconds(45)) {
                try await client.functions.invoke(
                    "extract-quote",
                    options: FunctionInvokeOptions(body: request)
                )
            }
        } catch is TimedOutError {
            throw QuoteError.extractionTimedOut
        }
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
}

private nonisolated struct ExtractRequest: Encodable, Sendable {
    let transcript: String
    let rate_card: [RateCardPayload]
    let currency: String
    /// The user's trade. The prompt has had a slot for this since it was
    /// written and nothing ever filled it — "eight of the 20 mil" is cable to
    /// an electrician and pipe to a plumber, and the model was guessing.
    let trade_context: String?
    /// The user's default tax rate, so the model can speak to tax in the quote.
    /// The stored total is still computed from this rate on save, not read back
    /// out of the response — the LLM is never trusted for math.
    let tax_rate: Double?
}

private nonisolated struct RateCardPayload: Encodable, Sendable {
    let name: String
    let unit: String?
    let unit_price: Double?
    let type: String
}

private nonisolated struct ExtractResponse: Decodable, Sendable {
    let quote: ExtractedQuote
}

private nonisolated struct ExtractedQuote: Decodable, Sendable {
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

private nonisolated struct ExtractedCustomer: Decodable, Sendable {
    let name: String?
    let address: String?
}

private nonisolated struct ExtractedLineItem: Decodable, Sendable {
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
