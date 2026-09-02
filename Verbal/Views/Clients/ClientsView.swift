//
//  ClientsView.swift
//  Verbal
//
//  The people you've quoted for, and what you quoted them.
//
//  A quiet, recent-first directory. Each row gives the client's quote count,
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
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    private static let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

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

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                clientSkeleton(titleWidth: 132, detailWidth: 96)
                clientSkeleton(titleWidth: 154, detailWidth: 122)
                clientSkeleton(titleWidth: 104, detailWidth: 86)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .shimmer(active: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your clients")
    }

    private func clientSkeleton(titleWidth: CGFloat, detailWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Color(.separator))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 8) {
                skeletonBar(width: titleWidth, height: 15)
                skeletonBar(width: detailWidth, height: 11)
            }
            Spacer(minLength: 12)
            skeletonBar(width: 18, height: 11)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.cardSurface), in: Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
    }

    private var feed: some View {
        List {
            sectionTitle
            ForEach(filtered) { client in
                clientRow(client)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var sectionTitle: some View {
        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
             ? "Recent Clients"
             : "Search Results")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))
    }

    private func clientRow(_ client: Client) -> some View {
        NavigationLink(value: ClientKey(id: client.id, name: client.name)) {
            HStack(alignment: .center, spacing: 12) {
                InitialsAvatar(name: client.name, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(client.name)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color(.mainText))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if let total = client.singleCurrencyTotal {
                            Text(total)
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color(.mainText))
                                .lineLimit(1)
                        }
                    }

                    Text(meta(for: client))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(.cardSurface), in: Self.cardShape)
            .overlay(Self.cardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.10),
                    radius: 8, x: 0, y: 3)
            .contentShape(.contextMenuPreview, Self.cardShape)
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(accessibilityLabel(for: client))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
    }

    private func summary(for client: Client) -> String {
        let count = "\(client.quotes.count) quote\(client.quotes.count == 1 ? "" : "s")"
        let value = client.singleCurrencyTotal.map { "\(count) · \($0)" } ?? count
        guard let activity = activity(for: client) else { return value }
        return "\(value) · \(activity)"
    }

    private func meta(for client: Client) -> String {
        let count = "\(client.quotes.count) quote\(client.quotes.count == 1 ? "" : "s")"
        guard let activity = activity(for: client) else { return count }
        return "\(count) · \(activity)"
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
