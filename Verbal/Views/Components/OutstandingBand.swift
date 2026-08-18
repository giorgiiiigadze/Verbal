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

    /// The total, when reaching it meant fetching a rate table. Nil whenever
    /// today's cache could answer on its own, which is nearly always.
    @State private var fetchedTotal: ConvertedTotal?
    /// The figure on screen. Trails `total` so a change the user is watching —
    /// switching currency — rolls to its new value instead of snapping. Nil
    /// until the first figure arrives, and that first one is taken without
    /// animation: counting up from zero to a number that was known before the
    /// screen was drawn is a loading spinner with extra steps.
    @State private var shown: Double?
    /// Observed so the summary re-converts when the user changes currency.
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    /// Quotes with a client and no decision yet — the pipeline.
    private var outstanding: [QuoteSummary] {
        quotes.filter { $0.effectiveStatus == "sent" || $0.effectiveStatus == "viewed" }
    }

    /// The total as today's cached rates can give it — computed here in the
    /// view rather than awaited, so it is right on the first frame the band is
    /// drawn. Nil only when a quote is priced in a currency whose rate table
    /// hasn't been fetched today, which is the one case worth waiting for.
    private var immediateTotal: ConvertedTotal? {
        ConvertedTotal.cached(outstanding, in: currencyCode)
    }

    /// What the band knows, from whichever of the two got there.
    private var total: ConvertedTotal? { immediateTotal ?? fetchedTotal }

    /// Whether there is a pipeline to report.
    ///
    /// True the moment there is one — before a pending conversion finishes — so
    /// the total can shimmer in place rather than popping in fully formed.
    /// False once the conversion comes back with nothing it could price, which
    /// is the offline case.
    private var hasAnything: Bool {
        total.map { $0.counted > 0 } ?? !outstanding.isEmpty
    }

    /// The figure, formatted — read off `shown` so a change rolls, keeping the
    /// count and the "≈" of the total it is trailing.
    private var outstandingLabel: String {
        ConvertedTotal(amount: shown ?? total?.amount ?? 0,
                       counted: total?.counted ?? 0,
                       isApproximate: total?.isApproximate ?? false)
            .formatted(in: currencyCode)
    }

    /// Until a pending conversion lands the exact count isn't known, so fall
    /// back to the number of outstanding quotes rather than flashing "0 quotes".
    private var displayedOutstandingCount: Int {
        total?.counted ?? outstanding.count
    }

    /// Changes whenever the figure would — the quotes in play, their amounts
    /// and currencies, or the currency they're being shown in.
    private var outstandingSignature: String {
        outstanding.map { "\($0.id)|\($0.total)|\($0.currency ?? "")" }
            .joined(separator: ",") + "→" + currencyCode
    }

    /// Fetch what the cache couldn't supply, and only that.
    ///
    /// The arithmetic lives in `ConvertedTotal`, which the client page uses to
    /// answer the same question about one person.
    private func recalculateOutstanding() async {
        guard immediateTotal == nil else { return }
        fetchedTotal = await ConvertedTotal.of(outstanding, in: currencyCode)
    }

    /// How many, and how long the oldest has been sitting there.
    ///
    /// One line rather than two facts in opposite corners. The count used to sit
    /// baseline-aligned with the caption at the far right, where it belonged to
    /// nothing and read as a stray; both halves are about the same pile of
    /// quotes and say more side by side than apart.
    ///
    /// The age is read from `createdAt` because that's all a summary carries —
    /// there's no sent-at timestamp — so this says "oldest", not "sent", and
    /// doesn't claim to date something it can't see.
    private var detailLabel: String {
        let count = displayedOutstandingCount
        let quotes = "\(count) quote\(count == 1 ? "" : "s")"
        guard let oldest = outstanding.map(\.createdAt).min() else { return quotes }
        return "\(quotes) · oldest \(oldest.formatted(.relative(presentation: .named)))"
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
        // The first figure lands as it is; every one after it rolls. A figure
        // that was known before the screen was drawn has nothing to announce,
        // and announcing it anyway is what made this band look like it was
        // still loading. A currency switch is the opposite case — the user did
        // something and the motion is the answer.
        .onChange(of: total?.amount, initial: true) { _, amount in
            guard let amount else { return }
            guard shown != nil else {
                shown = amount
                return
            }
            withAnimation(.snappy(duration: 0.55)) { shown = amount }
        }
    }

    private var content: some View {
        // One column, three lines, nothing floating opposite anything. What the
        // figure is, the figure, and what it is made of — read top to bottom in
        // the order the question is asked.
        VStack(alignment: .leading, spacing: 3) {
            Text("Waiting on clients")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Always in the user's own currency, converting quotes priced in
            // another one — a raw sum across currencies is meaningless.
            //
            // Shown the instant it can be totalled, which is nearly always: it
            // shimmers only while a rate table is genuinely being fetched.
            //
            // Slab, and a headline size. It is the one figure that sums up the
            // whole tab, and the app already keeps the serif for the things a
            // page is about — its headings, a quote's title, a client's name.
            //
            // Monospaced so the digits don't shuffle sideways as it rolls.
            Text(outstandingLabel)
                .font(.robotoSlab(28, relativeTo: .title).monospacedDigit())
                .foregroundStyle(Color(.mainText))
                .contentTransition(.numericText(value: shown ?? 0))
                .shimmer(active: total == nil)
            // The total on its own is a fact. How many it covers, and how long
            // the oldest has waited, is the part that says whether anything
            // needs chasing.
            Text(detailLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The band answers "how much is in play"; the threads below answer
        // "with whom". Set off by more than the gap between two client cards so
        // the reader sees a summary and then a list, rather than a first list
        // item that happens to look different.
        //
        // Inside `content` rather than at the call site: this view draws
        // nothing at all when nothing is outstanding, and padding on the
        // outside of nothing is a gap above the first client for no reason.
        .padding(.bottom, 12)
    }
}
