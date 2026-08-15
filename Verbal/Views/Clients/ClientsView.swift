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
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The container: the client, and the shape you tap to fold their quotes
    /// away. A card so it reads as the parent the thread hangs from, with the
    /// chevron carrying the open/closed state the way a comment's collapse does.
    private func clientHeader(_ client: Client) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { toggleCollapse(client) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isExpanded(client) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                    // No animation on the glyph swap itself — the thread opening
                    // is the motion; a spinning chevron on top is noise.
                    .animation(nil, value: isExpanded(client))

                InitialsAvatar(name: client.name, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name)
                        .font(.callout.weight(.semibold))
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

    /// The replies: a vertical rail with the client's quotes indented off it,
    /// each opening its own detail. The rail sits roughly under the avatar so
    /// the eye reads the quotes as belonging to the name above them.
    private func quotesThread(_ client: Client) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 2)
                .padding(.leading, 26)

            VStack(spacing: 10) {
                ForEach(client.quotes) { quote in
                    quoteReply(quote)
                }
            }
        }
        .padding(.trailing, 2)
    }

    private func quoteReply(_ quote: QuoteSummary) -> some View {
        ZStack {
            QuoteRow(quote: quote, unpricedCount: unpricedCount(for: quote))
            // Zero-opacity link, the same trick Home uses to navigate a row
            // without the default chevron landing on the row's own layout.
            NavigationLink {
                QuoteDetailView(
                    quote: quote,
                    initialLineItems: session.lineItems(for: quote.id) ?? [],
                    onDeleted: {}
                )
            } label: { EmptyView() }
            .opacity(0)
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
