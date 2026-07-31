//
//  HomeView.swift
//  Verbal
//
//  The "Your quotes" tab: a searchable, filterable, status-grouped list of the
//  user's quotes with pin / share / duplicate / status / delete actions.
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Binding var showCreate: Bool
    @State private var quotes: [QuoteSummary] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var filter: QuoteFilter = .all
    @State private var shareTarget: QuoteSummary?
    @State private var quoteToDelete: QuoteSummary?
    @State private var quoteToDuplicate: QuoteSummary?
    @State private var searchText = ""
    @State private var toast: Toast?
    /// True when the last fetch failed — distinguishes "no quotes" from
    /// "couldn't reach the server".
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if quotes.isEmpty && !hasLoaded {
                    // Still loading first paint — stay blank, not "no quotes".
                    Color(.homeBackground)
                } else if quotes.isEmpty && loadFailed {
                    // Don't claim the account is empty when the fetch failed.
                    errorState
                } else if quotes.isEmpty {
                    emptyState
                } else if sections.isEmpty {
                    // Quotes exist, but the search or filter excluded them all.
                    noMatchesState
                } else {
                    quotesList
                }
            }
            .background(Color(.homeBackground))
            .navigationTitle("Your quotes")
            .searchable(text: $searchText, prompt: "Search quotes")
            .searchToolbarBehavior(.minimize)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(QuoteFilter.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(item: $shareTarget) { quote in
                ShareQuotePanel(title: quote.displayTitle,
                                subtitle: "Total \(AppCurrency.format(quote.total, code: quote.currency)) · \(quote.status.capitalized)",
                                shareText: shareText(for: quote)) {
                    Task { await markSent(quote) }
                }
            }
            .task {
                // Seed instantly from the data preloaded during the splash so
                // the list appears with no empty-state flash, then refresh.
                if !hasLoaded {
                    quotes = session.quotes
                    hasLoaded = session.listsLoaded
                }
                await load()
            }
            .refreshable { await load() }
            .alert("Delete this quote?", isPresented: Binding(
                get: { quoteToDelete != nil },
                set: { if !$0 { quoteToDelete = nil } }
            ), presenting: quoteToDelete) { quote in
                Button("Delete", role: .destructive) {
                    Task { await delete(quote) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { quote in
                Text("This permanently deletes “\(quote.displayTitle)”. This can't be undone.")
            }
            .alert("Duplicate this quote?", isPresented: Binding(
                get: { quoteToDuplicate != nil },
                set: { if !$0 { quoteToDuplicate = nil } }
            ), presenting: quoteToDuplicate) { quote in
                Button("Duplicate") {
                    Task { await duplicate(quote) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { quote in
                Text("This creates a copy of “\(quote.displayTitle)” as a new draft.")
            }
            .toast($toast)
        }
        // Presented from outside the NavigationStack: attaching this sheet to
        // the content inside the stack (which also owns a minimizing
        // .searchable toolbar) corrupts the navigation bar after dismissal —
        // broken title layout and lost push transitions on the next push.
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
            QuoteRecordingView()
                .environment(session)
        }
    }

    // MARK: - List

    private var quotesList: some View {
        List {
            // Money in play, above the list — the number worth opening the app
            // for. Hidden while searching or filtering, when it'd be misleading.
            if !outstanding.isEmpty, searchQuery.isEmpty, filter == .all {
                outstandingSummary
                    // Full-bleed tinted band rather than a floating card, so the
                    // top of the screen reads as its own header zone.
                    .listRowBackground(
                        Color(.royalBlue25)
                            .overlay(alignment: .bottom) {
                                // Hairline where the band meets the page.
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(height: 0.5)
                            }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
            }

            ForEach(sections, id: \.title) { section in
                // Header as a normal row (not a Section header) so it scrolls
                // away with the content instead of pinning to the top.
                Text(section.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 20))

                ForEach(section.quotes) { quote in
                    ZStack {
                        QuoteRow(quote: quote)
                        // Zero-opacity link so the row navigates without the
                        // default trailing chevron.
                        NavigationLink {
                            QuoteDetailView(quote: quote,
                                            initialLineItems: session.lineItems(for: quote.id) ?? []) {
                                quotes.removeAll { $0.id == quote.id }
                                // Delay so the toast animates in on the
                                // now-visible Home, after the detail view's
                                // pop finishes (setting it mid-dismiss shows
                                // it off-screen and it's effectively missed).
                                Task {
                                    try? await Task.sleep(for: .seconds(0.4))
                                    toast = Toast(style: .success, message: "Quote deleted")
                                }
                            }
                            .environment(session)
                        } label: { EmptyView() }
                        .opacity(0)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .onAppear {
                        // Warm the cache so tapping opens the detail with line
                        // items already on screen.
                        Task { await session.prefetchLineItems(for: quote.id) }
                    }
                    .contextMenu { quoteMenu(for: quote) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // No .destructive role: it would animate the row out
                        // on tap, before the confirmation alert is answered.
                        Button {
                            quoteToDelete = quote
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)

                        Button {
                            shareTarget = quote
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(Color(.royalBlue300))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    /// Quotes with a client and no decision yet — the pipeline.
    private var outstanding: [QuoteSummary] {
        quotes.filter { $0.status == "sent" || $0.status == "viewed" }
    }

    private var outstandingSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting on clients")
                    .font(.caption)
                    .foregroundStyle(Color(.blueAccentText))
                Text(AppCurrency.format(outstanding.reduce(0) { $0 + $1.total },
                                        code: outstanding.first?.currency))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
            }
            Spacer(minLength: 8)
            Text("\(outstanding.count) quote\(outstanding.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(Color(.blueAccentText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Long-press context menu for a quote card.
    @ViewBuilder
    private func quoteMenu(for quote: QuoteSummary) -> some View {
        Button {
            Task { await togglePin(quote) }
        } label: {
            Label(quote.pinned ? "Unpin" : "Pin",
                  systemImage: quote.pinned ? "pin.slash" : "pin")
        }
        Button {
            shareTarget = quote
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            quoteToDuplicate = quote
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Menu {
            ForEach(selectableStatuses, id: \.self) { option in
                Button {
                    Task { await changeStatus(quote, to: option) }
                } label: {
                    Label(statusLabel(for: option), systemImage: statusIcon(for: option))
                }
            }
        } label: {
            Label("Status", systemImage: "arrow.triangle.2.circlepath")
        }
        Divider()
        Button(role: .destructive) {
            quoteToDelete = quote
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// First run: an invitation into the core loop, not a note that the list
    /// is empty. This is the screen a new user meets straight after onboarding.
    private var emptyState: some View {
        placeholder(
            icon: "mic.fill",
            title: "Your first quote starts here",
            message: "Describe a job out loud and Verbal turns it into a priced quote."
        ) {
            Button {
                showCreate = true
            } label: {
                Text("Record a job")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(Color(.royalBlue600), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// Quotes exist but the active search or filter matched none of them.
    private var noMatchesState: some View {
        placeholder(
            icon: "magnifyingglass",
            title: "Nothing to show",
            message: searchQuery.isEmpty
                ? "No quotes are \(filter.label.lowercased()) right now."
                : "No quotes match “\(searchQuery)”."
        ) {
            Button("Clear search and filters") {
                searchText = ""
                filter = .all
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(.blueAccentText))
        }
    }

    /// The first load failed and there's nothing cached to fall back on.
    private var errorState: some View {
        placeholder(
            icon: "wifi.exclamationmark",
            title: "Couldn't load your quotes",
            message: "Check your connection and try again."
        ) {
            Button("Try again") {
                Task { await load() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(.blueAccentText))
        }
    }

    /// Shared centered layout for the empty / no-match / error screens.
    private func placeholder<Action: View>(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color(.blueAccentText))
                .frame(width: 64, height: 64)
                .background(Color(.royalBlue25), in: Circle())
                .padding(.bottom, 6)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(.mainText))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            action()
                .padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    /// Quotes grouped into status sections, honoring the active filter.
    /// Section titles include a count, e.g. "Waiting to hear back · 2".
    /// The trimmed search text, as typed (for display in the no-match state).
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sections: [(title: String, quotes: [QuoteSummary])] {
        let query = searchQuery.lowercased()
        let filtered = quotes.filter { quote in
            guard filter.matches(quote.status) else { return false }
            guard !query.isEmpty else { return true }
            return quote.displayTitle.lowercased().contains(query)
                || (quote.jobSummary?.lowercased().contains(query) ?? false)
        }
        // Pinned quotes get their own section at the very top and are excluded
        // from the status sections below so they aren't listed twice.
        let pinned = filtered.filter(\.pinned)
        let rest = filtered.filter { !$0.pinned }

        var groups: [QuoteStatusGroup: [QuoteSummary]] = [:]
        for quote in rest {
            groups[QuoteStatusGroup(status: quote.status), default: []].append(quote)
        }
        var result: [(title: String, quotes: [QuoteSummary])] = []
        if !pinned.isEmpty {
            result.append(("Pinned · \(pinned.count)", pinned))
        }
        result += QuoteStatusGroup.allCases.compactMap { group in
            guard let items = groups[group], !items.isEmpty else { return nil }
            return ("\(group.title) · \(items.count)", items)
        }
        return result
    }

    // MARK: - Data

    private func shareText(for quote: QuoteSummary) -> String {
        var lines = [quote.displayTitle]
        if let summary = quote.jobSummary, !summary.isEmpty { lines.append(summary) }
        return lines.joined(separator: "\n")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            quotes = try await QuoteService.fetchQuotes()
            loadFailed = false
        } catch {
            // Keep whatever we had on screen; the flag lets the empty state
            // report a failure instead of claiming there are no quotes.
            loadFailed = true
            if !quotes.isEmpty {
                toast = Toast(style: .error, message: "Couldn't refresh quotes")
            }
        }
        hasLoaded = true
    }

    private func delete(_ quote: QuoteSummary) async {
        do {
            try await QuoteService.deleteQuote(id: quote.id)
            quotes.removeAll { $0.id == quote.id }
            toast = Toast(style: .success, message: "Quote deleted")
        } catch {
            toast = Toast(style: .error, message: "Couldn't delete quote")
        }
    }

    /// Sharing a draft marks it as Sent (don't downgrade later statuses).
    private func markSent(_ quote: QuoteSummary) async {
        guard quote.status == "draft" else { return }
        do {
            try await QuoteService.updateStatus(id: quote.id, status: "sent")
            await load()
        } catch {
            // Keep the current status if the update failed.
        }
    }

    // MARK: - Context-menu actions

    /// Statuses offered in the status submenu, in workflow order.
    private let selectableStatuses = ["draft", "sent", "viewed", "accepted", "declined", "expired"]

    private func statusLabel(for status: String) -> String {
        switch status {
        case "draft": return "Draft"
        case "sent": return "Sent"
        case "viewed": return "Viewed"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "expired": return "Expired"
        default: return status.capitalized
        }
    }

    private func statusIcon(for status: String) -> String {
        switch status {
        case "draft": return "pencil"
        case "sent": return "paperplane"
        case "viewed": return "eye"
        case "accepted": return "checkmark.circle"
        case "declined": return "xmark.circle"
        case "expired": return "clock.badge.exclamationmark"
        default: return "circle"
        }
    }

    /// Optimistically toggle the pin, persist, and revert on failure.
    private func togglePin(_ quote: QuoteSummary) async {
        guard let index = quotes.firstIndex(where: { $0.id == quote.id }) else { return }
        let newValue = !quote.pinned
        // Fire with the optimistic update so the tap feels instant, not
        // gated on the round trip.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { quotes[index].pinned = newValue }
        do {
            try await QuoteService.setPinned(id: quote.id, pinned: newValue)
        } catch {
            withAnimation { quotes[index].pinned = quote.pinned }
        }
    }

    private func changeStatus(_ quote: QuoteSummary, to newStatus: String) async {
        guard newStatus != quote.status,
              let index = quotes.firstIndex(where: { $0.id == quote.id }) else { return }
        let previous = quote.status
        withAnimation { quotes[index].status = newStatus }
        do {
            try await QuoteService.updateStatus(id: quote.id, status: newStatus)
            // The user just won the job — make it land physically.
            if newStatus == "accepted" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            withAnimation { quotes[index].status = previous }
        }
    }

    private func duplicate(_ quote: QuoteSummary) async {
        do {
            try await QuoteService.duplicateQuote(id: quote.id)
            await load()
        } catch {
            // Leave the list unchanged if the copy failed.
        }
    }
}

// MARK: - Row

private struct QuoteRow: View {
    let quote: QuoteSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if quote.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(.royalBlue600))
                    }
                    Text(quote.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                }
                Text(quote.createdAt, format: .relative(presentation: .named))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(AppCurrency.format(quote.total, code: quote.currency))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
                statusPill
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(quote.pinned ? Color(.royalBlue25) : Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Small tinted capsule naming the quote's status — pale blue for the
    /// working states, green/red for the settled ones.
    private var statusPill: some View {
        Text(pillLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(pillForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(pillBackground, in: Capsule())
    }

    private var pillLabel: String {
        switch quote.status {
        case "draft": return "Draft"
        case "sent": return "Sent"
        case "viewed": return "Viewed"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "expired": return "Expired"
        default: return quote.status.capitalized
        }
    }

    private var pillForeground: Color {
        switch quote.status {
        case "draft": return .orange
        case "viewed": return Color(.blueAccentText)
        case "accepted": return .green
        case "declined": return .red
        case "expired": return .secondary
        default: return Color(.blueAccentText)
        }
    }

    private var pillBackground: Color {
        switch quote.status {
        case "draft": return .orange.opacity(0.14)
        case "viewed": return Color(.royalBlue50)
        case "accepted": return .green.opacity(0.14)
        case "declined": return .red.opacity(0.12)
        case "expired": return Color(.separator).opacity(0.5)
        default: return Color(.royalBlue25)
        }
    }
}

// MARK: - Status grouping & filtering

/// Status buckets shown as list sections (in display order).
private enum QuoteStatusGroup: CaseIterable, Hashable {
    case drafts, waiting, accepted, declined, expired, other

    init(status: String) {
        switch status {
        case "draft": self = .drafts
        case "sent", "viewed": self = .waiting
        case "accepted": self = .accepted
        case "declined": self = .declined
        case "expired": self = .expired
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .drafts: return "Drafts"
        case .waiting: return "Waiting to hear back"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .expired: return "Expired"
        case .other: return "Other"
        }
    }
}

/// Filter options for the toolbar menu.
enum QuoteFilter: CaseIterable, Hashable, Identifiable {
    case all, drafts, waiting, accepted, declined, expired

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "All"
        case .drafts: return "Drafts"
        case .waiting: return "Waiting to hear back"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .expired: return "Expired"
        }
    }

    private var statuses: Set<String>? {
        switch self {
        case .all: return nil
        case .drafts: return ["draft"]
        case .waiting: return ["sent", "viewed"]
        case .accepted: return ["accepted"]
        case .declined: return ["declined"]
        case .expired: return ["expired"]
        }
    }

    func matches(_ status: String) -> Bool {
        statuses?.contains(status) ?? true
    }
}
