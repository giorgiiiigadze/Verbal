//
//  ClientActivity.swift
//  Verbal
//
//  A client's quotes as something that can be plotted.
//
//  `ConvertedTotal` answers "how much, altogether" and drops the detail on the
//  way — which is all the figures at the top of a client page ever needed. A
//  chart needs the quotes back one at a time, each already in the currency the
//  page is showing, so the conversion happens once here and every figure on the
//  page is then derived from the same converted set rather than from its own
//  pass over the rates.
//

import Foundation

/// One quote of a client's, priced in the currency the page is showing.
struct ClientQuotePoint: Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// What the quote is called, for the label the chart shows on selection.
    let title: String
    /// The total, converted into the display currency.
    let amount: Double
    /// `effectiveStatus`, not `status` — a lapsed offer plots as expired rather
    /// than going on standing as money in play.
    let status: String
    /// True when a daily rate was used to reach `amount`.
    let isConverted: Bool

    var isWon: Bool { status == "accepted" }
    var isWaiting: Bool { status == "sent" || status == "viewed" }
    var isDeclined: Bool { status == "declined" }

    /// The same rule `ConvertedTotal` applies: a quote priced in a currency with
    /// no published rate is left out rather than plotted at the wrong height.
    /// Sorted oldest first, which is the order both chart shapes read in.
    static func of(_ quotes: [QuoteSummary], in code: String) async -> [ClientQuotePoint] {
        var points: [ClientQuotePoint] = []
        for quote in quotes {
            let quoteCode = quote.currency ?? code
            if quoteCode == code {
                points.append(ClientQuotePoint(id: quote.id,
                                               date: quote.createdAt,
                                               title: quote.displayTitle,
                                               amount: quote.total,
                                               status: quote.effectiveStatus,
                                               isConverted: false))
            } else if let rate = try? await FXService.rate(from: quoteCode, to: code) {
                points.append(ClientQuotePoint(id: quote.id,
                                               date: quote.createdAt,
                                               title: quote.displayTitle,
                                               amount: quote.total * rate,
                                               status: quote.effectiveStatus,
                                               isConverted: true))
            }
        }
        return points.sorted { $0.date < $1.date }
    }
}

/// The client's running totals at one moment: what they had been quoted by then,
/// and how much of it they had said yes to.
///
/// A quote is an event, not a level — there is no "amount" for a Tuesday nobody
/// sent anything on, which is why a line drawn through quote amounts describes
/// days that never happened. A running total is the opposite: it has a value
/// every day, holds flat while nothing happens, and steps when something does.
/// That is the quantity a chart can honestly draw a line through.
struct ClientRunningTotal: Identifiable {
    let date: Date
    /// Everything quoted up to and including this moment.
    let quoted: Double
    /// The accepted part of it.
    let won: Double
    /// The quote that stepped the totals here, for the dot the chart draws on
    /// it. Nil on the two synthetic ends — the zero the line rises from and the
    /// carry out to today.
    let quote: ClientQuotePoint?

    var id: Date { date }
}

extension Array where Element == ClientQuotePoint {
    /// These quotes as one figure, in the shape the page already formats.
    var total: ConvertedTotal {
        ConvertedTotal(amount: reduce(0) { $0 + $1.amount },
                       counted: count,
                       isApproximate: contains(where: \.isConverted))
    }

    var won: [ClientQuotePoint] { filter(\.isWon) }
    var waiting: [ClientQuotePoint] { filter(\.isWaiting) }
    var declined: [ClientQuotePoint] { filter(\.isDeclined) }

    func within(_ range: ClientRange, now: Date = .now) -> [ClientQuotePoint] {
        guard let cutoff = range.cutoff(now: now) else { return self }
        return filter { $0.date >= cutoff }
    }

    /// These quotes as two lines climbing left to right.
    ///
    /// Each entry carries the totals *after* its quote, so the dot the chart
    /// puts on it sits at the top of its own riser rather than at the foot of
    /// it. Quotes sharing a date give two entries at the same moment, which
    /// draws as one taller step and needs no special case.
    ///
    /// It opens on a zero — at `start` when a window is chosen, otherwise just
    /// before the earliest quote — so the first step rises off the floor rather
    /// than beginning mid-air. And it closes at `now` rather than at the last
    /// quote: the flat run out to today is how a client who has gone quiet
    /// looks quiet, and a series that stops at their last quote hides exactly
    /// the thing worth seeing.
    func runningTotals(from start: Date? = nil, now: Date = .now) -> [ClientRunningTotal] {
        guard let earliest = first?.date else { return [] }

        var quoted = 0.0
        var won = 0.0
        var series = [ClientRunningTotal(date: start ?? earliest.addingTimeInterval(-86_400),
                                         quoted: 0, won: 0, quote: nil)]

        for point in self {
            quoted += point.amount
            if point.isWon { won += point.amount }
            series.append(ClientRunningTotal(date: point.date,
                                             quoted: quoted, won: won, quote: point))
        }

        series.append(ClientRunningTotal(date: now, quoted: quoted, won: won, quote: nil))
        return series
    }

    /// The window of the same length immediately before this one, which is what
    /// the figure at the top is compared against.
    func before(_ range: ClientRange, now: Date = .now) -> [ClientQuotePoint] {
        guard let cutoff = range.cutoff(now: now),
              let start = range.cutoff(now: cutoff) else { return [] }
        return filter { $0.date >= start && $0.date < cutoff }
    }
}

/// How far back the page is looking.
///
/// Deliberately coarse. A trade quotes a client a handful of times a year, so
/// the day- and week-length windows a stock ticker offers would each hold one
/// quote or none, and a selector where three of five options draw the same
/// picture is a selector nobody touches.
enum ClientRange: String, CaseIterable, Identifiable {
    case m3, m6, y1, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .m3: return "3M"
        case .m6: return "6M"
        case .y1: return "1Y"
        case .all: return "All"
        }
    }

    /// Said out loud, for the line under the headline figure.
    var spoken: String? {
        switch self {
        case .m3: return "3 months"
        case .m6: return "6 months"
        case .y1: return "year"
        case .all: return nil
        }
    }

    private var months: Int? {
        switch self {
        case .m3: return 3
        case .m6: return 6
        case .y1: return 12
        case .all: return nil
        }
    }

    /// The oldest date this window includes. Nil for `.all`, which has none.
    func cutoff(now: Date = .now) -> Date? {
        guard let months else { return nil }
        return Calendar.current.date(byAdding: .month, value: -months, to: now)
    }

    /// The windows worth offering for a given history.
    ///
    /// A window earns its place only when it both contains quotes and leaves
    /// some out — otherwise it draws exactly what "All" draws, and offering the
    /// user four ways to see one picture is worse than offering none. A client
    /// whose whole history fits inside three months gets no selector at all.
    static func available(for points: [ClientQuotePoint], now: Date = .now) -> [ClientRange] {
        allCases.filter { range in
            guard let cutoff = range.cutoff(now: now) else { return true }
            return points.contains { $0.date >= cutoff } && points.contains { $0.date < cutoff }
        }
    }
}
