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

    /// The same sum, from today's cached rates alone.
    ///
    /// `of` is `async` because a rate may have to be fetched, and a view that
    /// can only reach its figure through an `async` call has no figure on its
    /// first frame — it draws a placeholder and fills it in, which reads as
    /// loading even when every quote is already in the currency being shown.
    /// This answers during `body` when it can, and says so plainly when it
    /// can't: `nil` means at least one quote needs a rate table that hasn't
    /// been fetched today, and only `of` can finish the job.
    ///
    /// Every other rule is `of`'s, deliberately — the two are read off the same
    /// quotes on the same screen and must never disagree.
    static func cached(_ quotes: [QuoteSummary], in code: String) -> ConvertedTotal? {
        var sum = 0.0
        var counted = 0
        var converted = false

        for quote in quotes {
            let quoteCode = quote.currency ?? code
            switch FXService.cachedRate(from: quoteCode, to: code) {
            case .known(let rate):
                sum += quote.total * rate
                counted += 1
                // Off the codes, not off the rate: a pair sitting at exactly
                // 1.0 today is still a day's rate, and still earns the "≈".
                if quoteCode != code { converted = true }
            case .unsupported:
                continue
            case .needsFetch:
                return nil
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
