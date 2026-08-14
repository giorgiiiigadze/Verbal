//
//  ClientsView.swift
//  Verbal
//
//  The people you've quoted for, and what you quoted them.
//
//  Built from the quotes already in the session rather than from a fetch of its
//  own: the list is preloaded at launch and kept current by Home, so this tab
//  paints instantly, works with no signal, and can't disagree with the quote
//  list about who exists. The `customers` table holds the contact fields, and
//  this screen will need it when they become editable — but a name and a
//  history are what the tab is for, and both are already here.
//

import SwiftUI

struct ClientsView: View {
    @Environment(SessionStore.self) private var session
    @State private var searchText = ""

    /// Everyone with a name on at least one quote, most recently quoted first.
    ///
    /// Grouped case-insensitively for the same reason `customerID(named:)`
    /// matches that way: "Marina Kapanadze" and "marina kapanadze" are one
    /// person, and a list that says     rotherwise is a list of typos.
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
            if clients.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                noMatches
            } else {
                list
            }
        }
        .background(Color(.homeBackground))
        .navigationTitle("Clients")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search clients")
        .searchToolbarBehavior(.minimize)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { client in
                    NavigationLink {
                        ClientDetailView(client: client)
                    } label: {
                        row(client)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func row(_ client: Client) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(client.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
                Text(client.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Only when every one of their quotes is priced in the same
            // currency. Adding two currencies into one figure would be a number
            // that is true of nothing.
            if let total = client.singleCurrencyTotal {
                Text(total)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

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
