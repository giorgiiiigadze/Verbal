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

    /// How many of a client's quotes the thread shows before it offers the
    /// rest. Enough to see the shape of recent work, few enough that the next
    /// client is still on the screen.
    private static let previewCount = 3

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
        .modifier(ClientsDestinations())
        .navigationTitle("Clients")
        .navigationBarTitleDisplayMode(.inline)
        // Drawn out across the header, not minimised into a magnifying glass in
        // the corner. The field is the first thing anyone with more than a
        // screenful of clients wants, and a button that has to be tapped before
        // it becomes a field puts a step in front of it. `.always` keeps it
        // there while the feed scrolls rather than letting it hide on the way
        // down.
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search clients")
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
                // Money in play, at the top of the tab it is about. Hidden while
                // a search is running: it reports the whole account, and above a
                // narrowed list it would be describing something else.
                //
                // Scrolls away with the threads rather than sitting pinned —
                // the quotes are the point of the screen.
                if !isSearching {
                    OutstandingBand(quotes: session.quotes)
                }

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
                // Three, then a way through to the rest. The tab is a list of
                // people; a client with a long history used to bury everyone
                // after them, and scrolling past one person's back catalogue is
                // work the client's own page already exists to take.
                ClientThread(quotes: client.quotes,
                             limit: Self.previewCount,
                             seeAll: ClientKey(id: client.id, name: client.name))
                    .padding(.top, 8)
                    // A plain cross-fade, no slide. The quotes moving up out of
                    // the header read as the list glitching; fading them in
                    // place while the cards below close the gap reads as calm.
                    .transition(.opacity)
            }
        }
    }

    /// The container: the client, and the shape you tap to fold their quotes
    /// away. A card so it reads as the parent the thread hangs from.
    ///
    /// Two targets in one row. The name opens the client's own page; the
    /// chevron folds the thread, the way a comment's collapse does. They sit at
    /// opposite ends with the total between them, so neither is a mis-tap of
    /// the other — which is why the chevron moved to the trailing edge before
    /// the page existed.
    private func clientHeader(_ client: Client) -> some View {
        HStack(spacing: 12) {
            // By value, like the quotes below. A closure link would build this
            // page outside the stack, and the quote destination declared on
            // this screen would then be out of scope for the thread at the foot
            // of it — which is how tapping a quote there did nothing at all.
            NavigationLink(value: ClientKey(id: client.id, name: client.name)) {
                HStack(spacing: 12) {
                    // 44, against the ~40 of the two lines beside it. Big enough
                    // to be the thing you find the row by, and no bigger — past
                    // that the header outgrows the quote cards hanging off it,
                    // which is the hierarchy the wrong way up.
                    InitialsAvatar(name: client.name, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        // Slab, like the headings on Home and a quote's own
                        // title. A client is a name the app is filed under
                        // rather than a field on a row, and the serif is what
                        // the app uses to say so — the quotes hanging beneath
                        // keep the system face, so the parent and its thread
                        // stay told apart.
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
                }
                // The link takes the whole of its half, blank space included,
                // or the row only opens where there happens to be ink.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { toggleCollapse(client) }
            } label: {
                Image(systemName: isExpanded(client) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    // A thumb-sized target around a 12pt glyph. Sharing a row
                    // with a link, the mark itself is far too small to be the
                    // whole of it.
                    .frame(width: 34, height: 34)
                    .contentShape(.rect)
                    // No animation on the glyph swap itself — the thread opening
                    // is the motion; a spinning chevron on top is noise.
                    .animation(nil, value: isExpanded(client))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
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
