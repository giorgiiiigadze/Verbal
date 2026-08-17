//
//  OutstandingBand.swift
//  Verbal
//
//  Money in play: what has gone out to clients and not been answered yet.
//
//  It lived on Home, where tapping it filtered the list to those quotes. On the
//  Clients tab there is nothing for it to filter, so it is a read-out — no
//  chevron, no press state. A control that looks tappable and isn't is worse
//  than plain text.
//

import SwiftUI

struct OutstandingBand: View {
    /// Every quote the account has. The band picks its own out of them rather
    /// than being handed a filtered list, so the caller doesn't have to know
    /// which statuses count as waiting.
    let quotes: [QuoteSummary]

    /// Outstanding quotes converted into the user's currency. Nil until the
    /// first calculation finishes.
    @State private var outstandingTotal: Double?
    /// Quotes actually included above — a pair with no available rate is left
    /// out rather than silently added at the wrong value.
    @State private var outstandingCount = 0
    /// True when at least one quote needed converting, so the figure is
    /// a daily-rate approximation rather than an exact sum.
    @State private var outstandingIsApproximate = false
    /// The figure the band actually shows. Trails `outstandingTotal` so it can
    /// roll up to it — from zero on first load, and between values when the
    /// currency changes — rather than snapping.
    @State private var animatedOutstanding: Double = 0
    /// Observed so the summary re-converts when the user changes currency.
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    /// Quotes with a client and no decision yet — the pipeline.
    private var outstanding: [QuoteSummary] {
        quotes.filter { $0.effectiveStatus == "sent" || $0.effectiveStatus == "viewed" }
    }

    /// Whether there is a pipeline to report.
    ///
    /// True the moment there is one — before the conversion finishes — so the
    /// total can shimmer and count up in place rather than popping in fully
    /// formed. False once the conversion comes back with nothing it could
    /// price, which is the offline case.
    private var hasAnything: Bool {
        outstandingTotal == nil ? !outstanding.isEmpty : outstandingCount > 0
    }

    /// The rolling figure, formatted — reads off `animatedOutstanding` so the
    /// digits count up rather than the final number appearing at once.
    private var outstandingLabel: String {
        let formatted = AppCurrency.format(animatedOutstanding, code: currencyCode)
        return outstandingIsApproximate ? "≈ \(formatted)" : formatted
    }

    /// Until the conversion lands the exact count isn't known, so fall back to
    /// the number of outstanding quotes rather than flashing "0 quotes".
    private var displayedOutstandingCount: Int {
        outstandingTotal == nil ? outstanding.count : outstandingCount
    }

    /// Changes whenever the figure would — the quotes in play, their amounts
    /// and currencies, or the currency they're being shown in.
    private var outstandingSignature: String {
        outstanding.map { "\($0.id)|\($0.total)|\($0.currency ?? "")" }
            .joined(separator: ",") + "→" + currencyCode
    }

    /// Convert each outstanding quote into the user's currency and total them.
    /// A pair with no published rate is excluded from both the sum and the
    /// count, so the figure is never quietly wrong.
    private func recalculateOutstanding() async {
        let target = currencyCode
        var sum = 0.0
        var counted = 0
        var converted = false

        for quote in outstanding {
            let code = quote.currency ?? target
            if code == target {
                sum += quote.total
                counted += 1
            } else if let rate = try? await FXService.rate(from: code, to: target) {
                sum += quote.total * rate
                counted += 1
                converted = true
            }
        }

        outstandingTotal = sum
        outstandingCount = counted
        outstandingIsApproximate = converted
    }

    /// Age of the oldest quote still waiting on a client.
    ///
    /// Read from `createdAt` because that's all a summary carries — there's no
    /// sent-at timestamp — so this says "oldest", not "sent", and doesn't claim
    /// to date something it can't see.
    private var oldestLabel: String? {
        guard let oldest = outstanding.map(\.createdAt).min() else { return nil }
        return "Oldest · \(oldest.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        // The emptiness check is inside the body rather than at the call site,
        // and the modifiers below hang off the outer view rather than off the
        // content.
        //
        // Both matter. A caller cannot read this view's state, so it cannot
        // know whether the conversion found anything; and a band that removes
        // itself loses that state, comes back with a nil total, decides it has
        // something after all, converts again, and flickers forever. Staying
        // put with nothing drawn is what breaks that circle.
        Group {
            if hasAnything { content }
        }
        .task(id: outstandingSignature) { await recalculateOutstanding() }
        // Roll the figure up whenever the conversion produces a new one — from
        // zero on first load, and between values when the currency changes.
        .onChange(of: outstandingTotal, initial: true) { _, total in
            withAnimation(.snappy(duration: 0.55)) { animatedOutstanding = total ?? 0 }
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting on clients")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Always in the user's own currency, converting quotes priced
                // in another one — a raw sum across currencies is meaningless.
                //
                // It shimmers while the conversion runs, then rolls up to the
                // figure — the app's "working on it" motion, the same touch the
                // generator has, on the number worth opening the app for.
                // Slab, and a headline size. It is the one figure that sums
                // up the whole tab, and the app already keeps the serif for
                // the things a page is about — its headings, a quote's title,
                // a client's name. Losing the blue fill left it quiet; the
                // weight comes back through size instead of colour.
                //
                // Monospaced so the digits don't shuffle sideways as it rolls.
                Text(outstandingLabel)
                    .font(.robotoSlab(28, relativeTo: .title).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
                    .contentTransition(.numericText(value: animatedOutstanding))
                    .shimmer(active: outstandingTotal == nil)
                // The total on its own is a fact. The age is the part that says
                // whether anything needs chasing.
                if let oldestLabel {
                    Text(oldestLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            // Secondary, where this was `blueAccentText` — the colour was
            // marking the tappable half of a band that no longer is one.
            Text("\(displayedOutstandingCount) quote\(displayedOutstandingCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
