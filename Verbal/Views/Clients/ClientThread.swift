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
    /// Whether the quotes hang off a rail or simply stack.
    ///
    /// The rail's whole job is to say "these belong to the card above", which is
    /// a thing worth saying in the tab, where several clients' quotes run down
    /// one screen. A client's own page has one client on it and says so in
    /// thirty-point type at the top, so there the rail is a line drawn around a
    /// list to no end.
    var showsRail: Bool = true

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
        .padding(.leading, showsRail ? 20 : 0)
    }

    private func quoteReply(_ quote: QuoteSummary, isLast: Bool) -> some View {
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
                     clientIsKnown: true)
        }
        .buttonStyle(.plain)
        // The vertical padding is inside the connector's drawing area, so the
        // rail carries straight through the gaps between cards rather than
        // breaking at each one.
        .padding(.vertical, 5)
        .padding(.leading, showsRail ? ThreadConnector.gutter : 0)
        .background(alignment: .leading) {
            if showsRail {
                ThreadConnector(isLast: isLast)
                    .stroke(Color(.separator),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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

/// One person, as something that can be pushed.
///
/// The client's own `id` rather than the `Client` itself: a navigation value
/// has to keep the same hash for as long as its screen is up, and `Client`
/// hashes over its quotes — so editing one from that very screen would change
/// the value the stack is holding and pull the page out from under the user.
/// A key can't go stale, and the page reads the person from the session anyway.
struct ClientKey: Hashable {
    /// Their case-folded name, which is what `Client.id` is.
    let id: String
    /// Carried so the page has something to put at the top in the moment after
    /// their last quote is deleted, before it is popped. Payload, not identity:
    /// equality and hashing are on `id` alone, the same reason a quote hashes
    /// on its own id.
    let name: String

    static func == (lhs: ClientKey, rhs: ClientKey) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Where a tapped client and a tapped quote go, for the Clients tab.
///
/// Both declared together, once, on the tab's root — and both pushed by value.
/// That pairing is the point: a screen pushed by a *closure* link is not built
/// by the stack, so the stack's destinations are out of scope inside it, and
/// the thread at the foot of a client's page had nowhere to push to. Declaring
/// a second copy on that page instead made one tap push twice. Pushing the
/// client by value too puts its page inside the stack, where the quote
/// destination below reaches it.
///
/// Rows are read from the session rather than taken from the pushed value,
/// which is a snapshot of whatever the list held when it was tapped.
struct ClientsDestinations: ViewModifier {
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ClientKey.self) { key in
                ClientDetailView(key: key)
            }
            .navigationDestination(for: QuoteSummary.self) { quote in
                QuoteDetailView(
                    quote: session.quotes.first { $0.id == quote.id } ?? quote,
                    initialLineItems: session.lineItems(for: quote.id) ?? [],
                    onDeleted: {}
                )
            }
    }
}
