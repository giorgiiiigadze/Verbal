//
//  ClientsView.swift
//  Verbal
//
//  The people you've quoted for, and what you quoted them.
//
//  A quiet, recent-first directory. Each card gives the client's quote count,
//  quoted value and last activity, then opens their complete history.
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
    /// Starts a new quote for a named client. Its owner owns the recorder sheet
    /// and quota check, so this grid only asks for the action.
    var onNewQuote: (String) -> Void = { _ in }
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var isSearching = false

    // FaceTime-like tiles: deliberately taller than they are wide, with a
    // generous continuous corner rather than the small rounded-rectangle used
    // elsewhere for compact controls.
    private static let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    private static let cardAspectRatio: CGFloat = 0.70

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

    var body: some View {
        Group {
            if clients.isEmpty && !session.listsLoaded {
                loadingState
            } else if clients.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                noMatches
            } else {
                feed
            }
        }
        .background(clientsBackground)
        .modifier(ClientsDestinations())
        .navigationTitle("Clients")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SearchWhenAsked(isActive: isSearching,
                                  text: $searchText,
                                  isPresented: $isSearching,
                                  prompt: "Search clients"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isSearching = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search clients")
            }
        }
        // Asked for on every appearance, so arriving here after recording or
        // deleting a quote shows that, rather than whatever the list happened to
        // hold when the app started. This screen keeps no copy of its own —
        // `clients` is derived from the session — so the refresh is the whole
        // update: the new client appears, and one whose last quote went is gone.
        .task {
            await session.refreshQuotes()
            await QuoteService.refreshCustomerContactCache()
        }
        .refreshable { await session.refreshQuotes() }
    }

    // MARK: - Feed

    private var clientsBackground: Color {
        colorScheme == .dark ? Color(.homeBackground) : .white
    }

    private var loadingState: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                clientSkeleton(titleWidth: 74, detailWidth: 60)
                clientSkeleton(titleWidth: 88, detailWidth: 68)
                clientSkeleton(titleWidth: 64, detailWidth: 52)
                clientSkeleton(titleWidth: 82, detailWidth: 64)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .shimmer(active: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your clients")
    }

    private func clientSkeleton(titleWidth: CGFloat, detailWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Circle()
                .fill(Color(.separator))
                .frame(width: 44, height: 44)
            skeletonBar(width: titleWidth, height: 15)
            skeletonBar(width: detailWidth, height: 11)
            skeletonBar(width: 52, height: 15)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .aspectRatio(Self.cardAspectRatio, contentMode: .fit)
        .background(Color(.cardSurface), in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
    }

    private var feed: some View {
        gridFeed
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var gridFeed: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(filtered) { client in
                    clientCard(client)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }

    private func clientCard(_ client: Client) -> some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink(value: ClientKey(id: client.id, name: client.name)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(client.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(2)
                        .frame(minHeight: 40, alignment: .topLeading)

                    Spacer(minLength: 8)

                    InitialsAvatar(name: client.name, size: 96)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta(for: client))
                            .font(.callout.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        if let total = client.singleCurrencyTotal {
                            Text(total)
                                .font(.callout.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color(.mainText))
                        }
                    }
                    .lineLimit(1)
                    .padding(.trailing, 50)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .aspectRatio(Self.cardAspectRatio, contentMode: .fit)
                .background(Color(.cardSurface), in: Self.cardShape)
                .overlay(Self.cardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.10),
                        radius: 8, x: 0, y: 3)
                .contentShape(.contextMenuPreview, Self.cardShape)
            }
            .navigationLinkIndicatorVisibility(.hidden)
            .buttonStyle(CardPressStyle())
            .accessibilityLabel(accessibilityLabel(for: client))

            Button { onNewQuote(client.name) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(.mainText))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .zIndex(1)
            .padding(16)
            .accessibilityLabel("Create a new quote for \(client.name)")
        }
    }

    private func summary(for client: Client) -> String {
        let count = "\(client.quotes.count) quote\(client.quotes.count == 1 ? "" : "s")"
        let value = client.singleCurrencyTotal.map { "\(count) · \($0)" } ?? count
        guard let activity = activity(for: client) else { return value }
        return "\(value) · \(activity)"
    }

    private func meta(for client: Client) -> String {
        "\(client.quotes.count) quote\(client.quotes.count == 1 ? "" : "s")"
    }

    private func activity(for client: Client) -> String? {
        guard let date = client.lastQuoted else { return nil }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 86_400 {
            return quoteRelativeLabel(date)
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func accessibilityLabel(for client: Client) -> String {
        "\(client.name), \(summary(for: client))"
    }

    // MARK: - Placeholder states

    /// Nobody has been named on a quote yet. Not a pitch — clients aren't a
    /// feature to adopt, they're a by-product of quoting with a name filled in,
    /// so the screen says where they come from and stops.
    private var emptyState: some View {
        EmptyStateMessage(
            icon: "person.2",
            assetIcon: "ClientsEmpty",
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
