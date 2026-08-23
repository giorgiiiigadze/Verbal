//
//  ClientThread.swift
//  Verbal
//
//  A client's quotes, hanging off a rail — a node each, down one spine.
//
//  Lifted out of `ClientsView` when the client page arrived: both screens draw
//  the same thread, and a second copy of a rail this fiddly would have drifted
//  from the first within a week.
//

import SwiftUI

struct ClientThread: View {
    let quotes: [QuoteSummary]
    /// Whether the quotes hang off a rail or simply stack.
    ///
    /// The rail's whole job is to say "these belong to the card above", which is
    /// a thing worth saying in the tab, where several clients' quotes run down
    /// one screen. A client's own page has one client on it and says so in
    /// thirty-point type at the top, so there the rail is a line drawn around a
    /// list to no end.
    var showsRail: Bool = true
    /// How many quotes to draw before the thread is cut short.
    ///
    /// A client with thirty quotes pushed everyone under them off the screen,
    /// which made the tab a list of one person's history rather than a list of
    /// people. Nil draws the lot — which is what the client's own page wants,
    /// being the place the cut-short thread sends you.
    var limit: Int? = nil
    /// Who the "See all" row pushes to. Without it the thread simply stops at
    /// the limit, silently, so the two are set together or not at all.
    var seeAll: ClientKey? = nil

    @Environment(SessionStore.self) private var session

    /// The quotes actually drawn, newest first as they already are.
    private var shown: [QuoteSummary] {
        guard let limit, quotes.count > limit else { return quotes }
        return Array(quotes.prefix(limit))
    }

    private var isTruncated: Bool { shown.count < quotes.count }

    /// A continuous rail down the left, a node on it for each quote, and a
    /// short arm from the node to the card at its mid-height. The rail runs
    /// through the siblings still to come and stops at the last node.
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, quote in
                // Not the last node when there is more below: the rail has to
                // carry on down into the "See all" row, or the thread would
                // close itself and then something would hang under the end.
                quoteReply(quote,
                           index: index,
                           isLast: !isTruncated && index == shown.count - 1)
                if index < shown.count - 1 {
                    Divider()
                        .padding(.leading, showsRail ? ThreadConnector.gutter : 0)
                }
            }
            if isTruncated, let seeAll {
                seeAllRow(seeAll)
            }
        }
        .padding(.leading, showsRail ? 20 : 0)
    }

    /// The end of a shortened thread: how many more there are, and the way to
    /// them.
    ///
    /// It hangs off the rail like a quote does — same gutter, same node, same
    /// arm turning in at its mid-height — so it reads as the thread finishing
    /// rather than a control parked underneath it. No card, though: a card
    /// would be a fourth quote. Type alone, in the secondary weight the rest of
    /// the row furniture uses.
    private func seeAllRow(_ key: ClientKey) -> some View {
        NavigationLink(value: key) {
            HStack(spacing: 4) {
                Text("See all \(quotes.count) quotes")
                    .font(.footnote.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
        .padding(.leading, showsRail ? ThreadConnector.gutter : 0)
        .background(alignment: .leading) {
            if showsRail {
                ZStack(alignment: .leading) {
                    ThreadConnector(isLast: true)
                        .stroke(Color(.separator),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(Color(.statusMutedText).opacity(0.45))
                        .frame(width: ThreadConnector.nodeRadius * 2,
                               height: ThreadConnector.nodeRadius * 2)
                        .offset(x: ThreadConnector.railX - ThreadConnector.nodeRadius)
                }
                .frame(width: ThreadConnector.gutter)
            }
        }
    }

    private func quoteReply(_ quote: QuoteSummary, index: Int, isLast: Bool) -> some View {
        // By value, not by closure. The destination then belongs to the stack
        // rather than to this row — and this row is rebuilt every time the
        // session's copy of a quote changes, which is every time the screen it
        // pushed edits something. A closure link left that pushed screen
        // detached from the list feeding it: the first status change landed and
        // every one after it went nowhere.
        //
        // The card itself is the link's label, so the whole row is the tap
        // target. Home gets away with a zero-opacity link because it's a List,
        // where a row is tappable on its own; here in a ScrollView an empty
        // label would have no area to tap.
        NavigationLink(value: quote) {
            // The header above this thread already names the client, so the
            // row drops it and keeps the timestamp.
            QuoteRow(quote: quote,
                     unpricedCount: unpricedCount(for: quote),
                     clientIsKnown: true,
                     cornerRadius: 0,
                     topCornerRadius: index == 0 ? 18 : 0,
                     bottomCornerRadius: index == shown.count - 1 ? 18 : 0,
                     showsBorder: false)
        }
        .buttonStyle(.plain)
        // Client quote rows stack as one flat list; the divider between rows is
        // enough separation here.
        .padding(.vertical, 0)
        .padding(.leading, showsRail ? ThreadConnector.gutter : 0)
        .background(alignment: .leading) {
            if showsRail {
                // The node is a filled circle rather than part of the path: a
                // stroked shape can only give a ring, and a hollow node on a
                // hairline rail reads as a gap in the line. Darker than the
                // rail too — the line is structure, the node is the quote.
                ZStack(alignment: .leading) {
                    ThreadConnector(isLast: isLast)
                        .stroke(Color(.separator),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(Color(.statusMutedText).opacity(0.45))
                        .frame(width: ThreadConnector.nodeRadius * 2,
                               height: ThreadConnector.nodeRadius * 2)
                        .offset(x: ThreadConnector.railX - ThreadConnector.nodeRadius)
                }
                .frame(width: ThreadConnector.gutter)
            }
        }
        // Warm the cache so tapping opens the detail with line items already on
        // screen, and so the unpriced badge has something to count.
        .onAppear {
            Task { await session.prefetchLineItems(for: quote.id) }
        }
    }

    /// Read from the prefetched line items, the same as Home does — the summary
    /// row can't see inside a quote on its own.
    private func unpricedCount(for quote: QuoteSummary) -> Int {
        (session.lineItems(for: quote.id) ?? []).filter(\.isMissingPrice).count
    }
}
