//
//  ClientThread.swift
//  Verbal
//
//  A client's quotes, hanging off a rail — the way replies hang off a comment.
//
//  Lifted out of `ClientsView` when the client page arrived: both screens draw
//  the same thread, and a second copy of a rail this fiddly would have drifted
//  from the first within a week.
//

import SwiftUI

struct ClientThread: View {
    let quotes: [QuoteSummary]

    @Environment(SessionStore.self) private var session

    /// The replies: a continuous rail down the left with each quote branching
    /// off it on a rounded elbow that meets the card at its mid-height — the
    /// way a comment thread curves into each reply. The rail runs straight
    /// through the siblings above the last one and closes into the final elbow.
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(quotes.enumerated()), id: \.element.id) { index, quote in
                quoteReply(quote, isLast: index == quotes.count - 1)
            }
        }
        .padding(.leading, 20)
    }

    private func quoteReply(_ quote: QuoteSummary, isLast: Bool) -> some View {
        // The card itself is the link's label, so the whole row is the tap
        // target. Home gets away with a zero-opacity link because it's a List,
        // where a row is tappable on its own; here in a ScrollView an empty
        // label would have no area to tap.
        NavigationLink {
            QuoteDetailView(
                quote: quote,
                initialLineItems: session.lineItems(for: quote.id) ?? [],
                onDeleted: {}
            )
        } label: {
            // The header above this thread already names the client, so the
            // row drops it and keeps the timestamp.
            QuoteRow(quote: quote,
                     unpricedCount: unpricedCount(for: quote),
                     clientIsKnown: true)
        }
        .buttonStyle(.plain)
        // The vertical padding is inside the connector's drawing area, so the
        // rail carries straight through the gaps between cards rather than
        // breaking at each one.
        .padding(.vertical, 5)
        .padding(.leading, ThreadConnector.gutter)
        .background(alignment: .leading) {
            ThreadConnector(isLast: isLast)
                .stroke(Color(.separator),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: ThreadConnector.gutter)
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
