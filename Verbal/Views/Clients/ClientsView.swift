//
//  ClientsView.swift
//  Verbal
//
//  The people you've quoted for, and what you quoted them.
//
//  A threaded feed rather than a list of links: each client is a container with
//  their quotes hanging off it, the way a comment sits above its replies. The
//  quotes are right there — no tap-through — expanded by default and collapsible
//  per client.
//
//  Built from the quotes already in the session rather than from a fetch of its
//  own: the list is preloaded at launch and kept current by Home, so this tab
//  paints instantly, works with no signal, and can't disagree with the quote
//  list about who exists. The `customers` table holds the contact fields, and a
//  full client profile will want them — but a name and a history are what the
//  tab is for, and both are already here.
//

import SwiftUI

struct ClientsView: View {
    @Environment(SessionStore.self) private var session
    @State private var searchText = ""
    /// Clients whose quotes are hidden. Empty by default, so every thread opens
    /// expanded — the quotes are the point of the screen, not a reveal.
    @State private var collapsed: Set<Client.ID> = []

    /// Everyone with a name on at least one quote, most recently quoted first.
    ///
    /// Grouped case-insensitively for the same reason `customerID(named:)`
    /// matches that way: "Marina Kapanadze" and "marina kapanadze" are one
    /// person, and a list that says otherwise is a list of typos.
    private var clients: [Client] {
        var byKey: [String: [QuoteSummary]] = [:]
        for quote in session.quotes {
            let name = (quote.clientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            byKey[name.lowercased(), default: []].append(quote)
        }
        // Built with an explicit loop, not `.compactMap(Client.init)`: the
        // initializer is main-actor isolated and a map closure is not, so the
        // reference can't be handed to it. The loop runs here on the main actor.
        var built: [Client] = []
        for quotes in byKey.values {
            if let client = Client(quotes) { built.append(client) }
        }
        return built.sorted {
            ($0.lastQuoted ?? .distantPast) > ($1.lastQuoted ?? .distantPast)
        }
    }

    private var filtered: [Client] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return clients }
        return clients.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// While a search is running, matches are shown open regardless of the
    /// collapse set — hiding the quotes someone is searching for would be odd.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isExpanded(_ client: Client) -> Bool {
        isSearching || !collapsed.contains(client.id)
    }

    private func toggleCollapse(_ client: Client) {
        if collapsed.contains(client.id) {
            collapsed.remove(client.id)
        } else {
            collapsed.insert(client.id)
        }
    }

    var body: some View {
        Group {
            if clients.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                noMatches
            } else {
                feed
            }
        }
        .background(Color(.homeBackground))
        .navigationTitle("Clients")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search clients")
        .searchToolbarBehavior(.minimize)
        // Asked for on every appearance, so arriving here after recording or
        // deleting a quote shows that, rather than whatever the list happened to
        // hold when the app started. This screen keeps no copy of its own —
        // `clients` is derived from the session — so the refresh is the whole
        // update: the new client appears, and one whose last quote went is gone.
        .task { await session.refreshQuotes() }
        .refreshable { await session.refreshQuotes() }
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(filtered) { client in
                    clientThread(client)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func clientThread(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            clientHeader(client)

            if isExpanded(client) {
                quotesThread(client)
                    .padding(.top, 8)
                    // A plain cross-fade, no slide. The quotes moving up out of
                    // the header read as the list glitching; fading them in
                    // place while the cards below close the gap reads as calm.
                    .transition(.opacity)
            }
        }
    }

    /// The container: the client, and the shape you tap to fold their quotes
    /// away. A card so it reads as the parent the thread hangs from, with the
    /// chevron carrying the open/closed state the way a comment's collapse does.
    private func clientHeader(_ client: Client) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { toggleCollapse(client) }
        } label: {
            HStack(spacing: 12) {
                // 44, against the ~40 of the two lines beside it. Big enough to
                // be the thing you find the row by, and no bigger — past that
                // the header outgrows the quote cards hanging off it, which is
                // the hierarchy the wrong way up.
                InitialsAvatar(name: client.name, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    // Slab, like the headings on Home and a quote's own title.
                    // A client is a name the app is filed under rather than a
                    // field on a row, and the serif is what the app uses to say
                    // so — the quotes hanging beneath keep the system face, so
                    // the parent and its thread stay told apart.
                    Text(client.name)
                        .font(.robotoSlab(17, relativeTo: .headline))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text(client.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Only when every one of their quotes is priced in the same
                // currency. Adding two currencies into one figure would be a
                // number that is true of nothing.
                if let total = client.singleCurrencyTotal {
                    Text(total)
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Trailing, where a disclosure belongs — and it leaves the
                // leading edge to the avatar, which now lines up with the rail
                // running down to the quotes below.
                Image(systemName: isExpanded(client) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    // No animation on the glyph swap itself — the thread opening
                    // is the motion; a spinning chevron on top is noise.
                    .animation(nil, value: isExpanded(client))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// The replies: a continuous rail down the left with each quote branching
    /// off it on a rounded elbow that meets the card at its mid-height — the
    /// way a comment thread curves into each reply. The rail runs straight
    /// through the siblings above the last one and closes into the final elbow.
    private func quotesThread(_ client: Client) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(client.quotes.enumerated()), id: \.element.id) { index, quote in
                quoteReply(quote, isLast: index == client.quotes.count - 1)
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

    // MARK: - Placeholder states

    /// Nobody has been named on a quote yet. Not a pitch — clients aren't a
    /// feature to adopt, they're a by-product of quoting with a name filled in,
    /// so the screen says where they come from and stops.
    private var emptyState: some View {
        EmptyStateMessage(
            icon: "person.2",
            title: "No clients yet",
            message: "Put a name on a quote and whoever you quoted for shows up here, with everything you've sent them."
        ) {
            EmptyView()
        }
    }

    private var noMatches: some View {
        EmptyStateMessage(
            icon: "magnifyingglass",
            title: "No matches",
            message: "No client's name contains “\(searchText)”."
        ) {
            EmptyView()
        }
    }
}

/// One person, and every quote with their name on it. Derived rather than
/// fetched, so it holds quotes rather than ids.
struct Client: Identifiable, Hashable {
    let name: String
    let quotes: [QuoteSummary]

    /// Case-folded, matching how the group was built — two spellings of one
    /// name must not become two rows with the same identity.
    var id: String { name.lowercased() }

    init?(_ quotes: [QuoteSummary]) {
        guard let first = quotes.first else { return nil }
        // The most recent spelling wins: it's the one they last typed, and so
        // the one most likely to be right.
        let newest = quotes.max { $0.createdAt < $1.createdAt } ?? first
        name = (newest.clientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.quotes = quotes.sorted { $0.createdAt > $1.createdAt }
    }

    var lastQuoted: Date? { quotes.map(\.createdAt).max() }

    var subtitle: String {
        let count = "\(quotes.count) quote\(quotes.count == 1 ? "" : "s")"
        guard let lastQuoted else { return count }
        return "\(count) · \(quoteDateLabel(lastQuoted))"
    }

    /// Their total, but only when there is one currency to state it in.
    var singleCurrencyTotal: String? {
        let codes = Set(quotes.map { $0.currency ?? AppCurrency.current.rawValue })
        guard let code = codes.first, codes.count == 1 else { return nil }
        return AppCurrency.format(quotes.reduce(0) { $0 + $1.total }, code: code)
    }

    static func == (lhs: Client, rhs: Client) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The thread line beside one quote: a vertical rail with a rounded elbow that
/// branches into the card at its mid-height.
///
/// The rail is drawn to the full height it's given (the card plus its vertical
/// padding), so stacking these leaves the rail unbroken between siblings. The
/// last quote gets no continuation below its elbow — the thread ends where it
/// turns in, the way the final reply closes a comment chain.
private struct ThreadConnector: Shape {
    var isLast: Bool

    /// Width of the connector column, and so where the elbow meets the card.
    static let gutter: CGFloat = 24

    private let railX: CGFloat = 7
    private let corner: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let rightX = rect.maxX

        if isLast {
            // Rail comes down and turns once into the card — nothing below it.
            path.move(to: CGPoint(x: railX, y: rect.minY))
            path.addLine(to: CGPoint(x: railX, y: midY - corner))
            path.addQuadCurve(to: CGPoint(x: railX + corner, y: midY),
                              control: CGPoint(x: railX, y: midY))
            path.addLine(to: CGPoint(x: rightX, y: midY))
        } else {
            // Rail runs the whole height for the siblings still to come…
            path.move(to: CGPoint(x: railX, y: rect.minY))
            path.addLine(to: CGPoint(x: railX, y: rect.maxY))
            // …and a rounded branch peels off it into this card.
            path.move(to: CGPoint(x: railX, y: midY - corner))
            path.addQuadCurve(to: CGPoint(x: railX + corner, y: midY),
                              control: CGPoint(x: railX, y: midY))
            path.addLine(to: CGPoint(x: rightX, y: midY))
        }
        return path
    }
}
