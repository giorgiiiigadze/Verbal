//
//  ClientActivity.swift
//  Verbal
//
//  A client's quotes in a common display currency.
//
//  The client page needs the quotes back one at a time, each already in the
//  currency it is showing, so conversion happens once here and its headline
//  figures are all derived from the same set.
//

import Foundation

/// One quote of a client's, priced in the currency the page is showing.
struct ClientQuotePoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// The total, converted into the display currency.
    let amount: Double
    /// `effectiveStatus`, not `status` — a lapsed offer plots as expired rather
    /// than going on standing as money in play.
    let status: String
    /// True when a daily rate was used to reach `amount`.
    let isConverted: Bool

    var isWon: Bool { status == "accepted" }
    /// The same rule `ConvertedTotal` applies: a quote priced in a currency with
    /// no published rate is left out rather than presented at the wrong value.
    /// Sorted oldest first for a stable, predictable result.
    static func of(_ quotes: [QuoteSummary], in code: String) async -> [ClientQuotePoint] {
        var points: [ClientQuotePoint] = []
        for quote in quotes {
            let quoteCode = quote.currency ?? code
            if quoteCode == code {
                points.append(ClientQuotePoint(id: quote.id,
                                               date: quote.createdAt,
                                               amount: quote.total,
                                               status: quote.effectiveStatus,
                                               isConverted: false))
            } else if let rate = try? await FXService.rate(from: quoteCode, to: code) {
                points.append(ClientQuotePoint(id: quote.id,
                                               date: quote.createdAt,
                                               amount: quote.total * rate,
                                               status: quote.effectiveStatus,
                                               isConverted: true))
            }
        }
        return points.sorted { $0.date < $1.date }
    }
}

extension Array where Element == ClientQuotePoint {
    /// These quotes as one figure, in the shape the page already formats.
    var total: ConvertedTotal {
        ConvertedTotal(amount: reduce(0) { $0 + $1.amount },
                       counted: count,
                       isApproximate: contains(where: \.isConverted))
    }

    var won: [ClientQuotePoint] { filter(\.isWon) }
}
