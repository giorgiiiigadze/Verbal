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
                quoteReply(quote, isLast: !isTruncated && index == shown.count - 1)
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
