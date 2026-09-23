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
    private enum SmartCollection: CaseIterable, Identifiable {
        case all
        case recent
        case followUp
        case upcoming

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "All Clients"
            case .recent: "Recent"
            case .followUp: "Follow Up"
            case .upcoming: "Upcoming"
            }
        }

        var systemImage: String {
            switch self {
            case .all: "person.2.fill"
            case .recent: "clock.fill"
            case .followUp: "bubble.left.and.bubble.right.fill"
            case .upcoming: "calendar"
            }
        }

        var tint: Color {
            switch self {
            case .all: .cyan
            case .recent: .indigo
            case .followUp: .orange
            case .upcoming: .yellow
            }
        }
    }

    private enum SortOrder: CaseIterable, Identifiable {
        case recent
        case name
        case quoteCount

        var id: Self { self }

        var title: String {
            switch self {
            case .recent: "Recent Activity"
            case .name: "Name"
            case .quoteCount: "Most Quotes"
            }
        }

        var systemImage: String {
            switch self {
            case .recent: "clock"
            case .name: "textformat"
            case .quoteCount: "doc.on.doc"
            }
        }
    }

    /// Starts a new quote for a named client. Its owner owns the recorder sheet
    /// and quota check, so this grid only asks for the action.
    var onNewQuote: (String) -> Void = { _ in }
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .recent
    @State private var selectedCollection: SmartCollection = .all

    // FaceTime-like tiles: deliberately taller than they are wide, with a
    // restrained continuous corner that keeps the grid crisp.
    private static let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private static let cardAspectRatio: CGFloat = 0.70
    /// The same adaptive surface used by Rate Card containers.
    private static let clientSurface = Color(.cardSurface)

    /// Everyone with a name on at least one quote. Presentation order is kept
    /// separate so the menu can change it without rebuilding the people.
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
        return built
    }

    private var filtered: [Client] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let collectionMatches = clients(in: selectedCollection)
        let matches = query.isEmpty
            ? collectionMatches
            : collectionMatches.filter { $0.name.localizedCaseInsensitiveContains(query) }

        return matches.sorted { lhs, rhs in
            switch sortOrder {
            case .recent:
                return (lhs.lastQuoted ?? .distantPast) > (rhs.lastQuoted ?? .distantPast)
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .quoteCount:
                if lhs.quotes.count != rhs.quotes.count {
                    return lhs.quotes.count > rhs.quotes.count
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var upcomingVisits: [ScheduledVisit] {
        session.visitStore.visits.filter {
            $0.recordedQuoteId == nil && $0.endDate >= .now
        }
    }

    private var upcomingClientKeys: Set<String> {
        Set(upcomingVisits.map(\.clientKey))
    }

    private func clients(in collection: SmartCollection) -> [Client] {
        switch collection {
        case .all:
            return clients
        case .recent:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)
                ?? .distantPast
            return clients.filter { ($0.lastQuoted ?? .distantPast) >= cutoff }
        case .followUp:
            return clients.filter { client in
                client.quotes.contains {
                    $0.effectiveStatus == "sent" || $0.effectiveStatus == "viewed"
                }
            }
        case .upcoming:
            return clients.filter { upcomingClientKeys.contains($0.id) }
        }
    }

    var body: some View {
        Group {
            if clients.isEmpty && !session.listsLoaded {
                loadingState
            } else if clients.isEmpty {
                emptyState
            } else {
                feed
            }
        }
        .background(clientsBackground)
        .modifier(ClientsDestinations())
        .navigationTitle("Clients")
        .navigationBarTitleDisplayMode(.inline)
        // The iOS 26 search toolbar starts as the full field beneath the title
        // and contracts to its compact native control as the grid scrolls.
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search clients")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Menu {
                        ForEach(SortOrder.allCases) { option in
                            Button {
                                sortOrder = option
                            } label: {
                                Label(option.title,
                                      systemImage: sortOrder == option
                                        ? "checkmark" : option.systemImage)
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }

                    Divider()

                    Button {
                        Task {
                            await session.refreshQuotes()
                            await QuoteService.refreshCustomerContactCache()
                        }
                    } label: {
                        Label("Refresh Clients", systemImage: "arrow.clockwise")
                    }

                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Label("Clear Search", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Client options")
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
            await session.visitStore.sync()
        }
        .refreshable {
            await session.refreshQuotes()
            await session.visitStore.sync()
        }
    }

    // MARK: - Feed

    private var clientsBackground: Color {
        Color(.homeBackground)
    }

    private var loadingState: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 18) {
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
        .background(Self.clientSurface, in: Self.cardShape)
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
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }

    private var gridFeed: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                smartCollections

                Text("Showing " + selectedCollection.title.lowercased())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if filtered.isEmpty {
                    filteredEmptyState
                        .frame(minHeight: 260)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 18) {
                        ForEach(filtered) { client in
                            clientCard(client)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }

    private var smartCollections: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("At a glance")
                    .font(.robotoSlab(24, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))

                Text("Find who needs attention or what's coming next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 16) {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(SmartCollection.allCases) { collection in
                        smartCollectionCard(collection)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smartCollectionCard(_ collection: SmartCollection) -> some View {
        let isSelected = selectedCollection == collection
        let glassTint: Color? = colorScheme == .dark
            ? nil
            : collection.tint.opacity(isSelected ? 0.52 : 0.26)
        let selectionStroke = colorScheme == .dark
            ? Color.white.opacity(0.30)
            : collection.tint.opacity(0.72)

        return Button {
            withAnimation(.snappy(duration: 0.24)) {
                selectedCollection = collection
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: collection.systemImage)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 18)

                Text(collection.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(collectionSubtitle(collection))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(Color(.mainText))
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(
                .regular
                    .tint(glassTint)
                    .interactive(),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(selectionStroke, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(collection.title), \(collectionSubtitle(collection))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func collectionSubtitle(_ collection: SmartCollection) -> String {
        let count = clients(in: collection).count
        switch collection {
        case .all:
            return clientCountText(count)
        case .recent:
            return count == 0 ? "No recent activity" : "\(count) active in 30 days"
        case .followUp:
            return count == 0 ? "Nothing waiting" : "\(count) awaiting a reply"
        case .upcoming:
            guard let next = upcomingVisits.min(by: { $0.date < $1.date }) else {
                return "Nothing scheduled"
            }
            return "Next visit \(next.dayText.lowercased())"
        }
    }

    private func clientCountText(_ count: Int) -> String {
        "\(count) client\(count == 1 ? "" : "s")"
    }

    private func clientCard(_ client: Client) -> some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink(value: ClientKey(id: client.id, name: client.name)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(client.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(2)
                        .frame(minHeight: 40, alignment: .topLeading)

                    Spacer(minLength: 8)

                    InitialsAvatar(name: client.name, size: 96)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta(for: client))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.mainText))

                        if let total = client.singleCurrencyTotal {
                            Text(total)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color(.mainText))
                        }
                    }
                    .lineLimit(1)
                    .padding(.trailing, 50)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .aspectRatio(Self.cardAspectRatio, contentMode: .fit)
                .background(Self.clientSurface, in: Self.cardShape)
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
                    .background(Self.clientSurface, in: Circle())
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

    private var filteredEmptyState: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let copy: (icon: String, title: String, message: String)

        if !query.isEmpty {
            copy = ("magnifyingglass", "No matches",
                    "No client in \(selectedCollection.title) contains “\(query)”.")
        } else {
            switch selectedCollection {
            case .all:
                copy = ("person.2", "No clients", "Your clients will appear here.")
            case .recent:
                copy = ("clock", "No recent clients",
                        "Nobody has had quote activity in the last 30 days.")
            case .followUp:
                copy = ("checkmark.circle", "You're all caught up",
                        "There are no sent or viewed quotes awaiting a reply.")
            case .upcoming:
                copy = ("calendar", "No upcoming clients",
                        "Clients with a future visit will appear here.")
            }
        }

        return EmptyStateMessage(
            icon: copy.icon,
            title: copy.title,
            message: copy.message
        ) {
            if selectedCollection != .all {
                EmptyStatePill(title: "Show all clients", icon: "person.2") {
                    withAnimation(.snappy(duration: 0.24)) {
                        selectedCollection = .all
                    }
                }
            }
        }
    }

}
