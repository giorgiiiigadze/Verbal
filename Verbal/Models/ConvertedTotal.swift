//
//  ConvertedTotal.swift
//  Verbal
//
//  A set of quotes added up in one currency.
//
//  A raw sum across currencies is a number that is true of nothing, so anything
//  priced elsewhere is converted first — and anything with no published rate is
//  left out of both the sum and the count rather than quietly added at the wrong
//  value. `counted` is what the figure actually covers, and `isApproximate` says
//  a daily rate was involved, which is what earns the "≈".
//

import Foundation

struct ConvertedTotal {
    let amount: Double
    /// How many of the quotes the amount covers. Fewer than were handed in means
    /// a rate was missing, not that a quote was worthless.
    let counted: Int
    /// True when at least one quote had to be converted, so the figure is a
    /// day's rate rather than an exact sum.
    let isApproximate: Bool

    static let none = ConvertedTotal(amount: 0, counted: 0, isApproximate: false)

    static func of(_ quotes: [QuoteSummary], in code: String) async -> ConvertedTotal {
        var sum = 0.0
        var counted = 0
        var converted = false

        for quote in quotes {
            let quoteCode = quote.currency ?? code
            if quoteCode == code {
                sum += quote.total
                counted += 1
            } else if let rate = try? await FXService.rate(from: quoteCode, to: code) {
                sum += quote.total * rate
                counted += 1
                converted = true
            }
        }
        return ConvertedTotal(amount: sum, counted: counted, isApproximate: converted)
    }

    /// The amount, with the "≈" that says a rate was used to reach it.
    func formatted(in code: String) -> String {
        let text = AppCurrency.format(amount, code: code)
        return isApproximate ? "≈ \(text)" : text
    }
}
