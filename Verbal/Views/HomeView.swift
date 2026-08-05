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
    /// Held while business details are collected; shared once that sheet closes.
    @State private var shareAfterDetails: QuoteSummary?
    @State private var quoteToDelete: QuoteSummary?
    @State private var quoteToDuplicate: QuoteSummary?
    @State private var searchText = ""
    @State private var toast: Toast?
    /// True when the last fetch failed — distinguishes "no quotes" from
    /// "couldn't reach the server".
    @State private var loadFailed = false
    /// Outstanding quotes converted into the user's currency. Nil until the
    /// first calculation finishes.
    @State private var outstandingTotal: Double?
    /// Quotes actually included above — a pair with no available rate is left
    /// out rather than silently added at the wrong value.
    @State private var outstandingCount = 0
    /// True when at least one quote needed converting, so the figure is
    /// a daily-rate approximation rather than an exact sum.
    @State private var outstandingIsApproximate = false
    /// Observed so the summary re-converts when the user changes currency.
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    var body: some View {
        NavigationStack {
            Group {
                if quotes.isEmpty && !hasLoaded {
                    // Still loading first paint — placeholders, not "no quotes".
                    loadingState
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
            .sheet(item: $shareAfterDetails) { quote in
                BusinessDetailsSheet {
                    // Continue to the share panel once the details sheet is
                    // gone, rather than stacking one on top of the other.
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))
                        shareTarget = quote
                    }
                }
                .environment(session)
            }
            .sheet(item: $shareTarget) { quote in
                ShareQuotePanel(title: quote.displayTitle,
                                subtitle: "Total \(AppCurrency.format(quote.total, code: quote.currency)) · \(quote.effectiveStatus.capitalized)",
                                shareText: shareText(for: quote),
                                document: pdfDocument(for: quote)) {
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
            // Bootstrap can finish after this view has already read an empty
            // list — signing in reaches Home before the preload returns. Take
            // what arrives rather than sitting on the empty copy.
            .onChange(of: session.listsLoaded) { _, loaded in
                guard loaded, quotes.isEmpty, !session.quotes.isEmpty else { return }
                quotes = session.quotes
                loadFailed = false
            }
            .task(id: outstandingSignature) { await recalculateOutstanding() }
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
            if outstandingTotal != nil, outstandingCount > 0, searchQuery.isEmpty, filter == .all {
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
                                withAnimation(Self.rowRemoval) {
                                    quotes.removeAll { $0.id == quote.id }
                                }
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
                            share(quote)
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
        quotes.filter { $0.effectiveStatus == "sent" || $0.effectiveStatus == "viewed" }
    }

    private var outstandingLabel: String {
        guard let outstandingTotal else { return "—" }
        let formatted = AppCurrency.format(outstandingTotal, code: currencyCode)
        return outstandingIsApproximate ? "≈ \(formatted)" : formatted
    }

    /// Convert each outstanding quote into the user's currency and total them.
    /// A pair with no published rate is excluded from both the sum and the
    /// count, so the figure is never quietly wrong.
    /// Changes whenever the figure would — the quotes in play, their amounts
    /// and currencies, or the currency they're being shown in.
    private var outstandingSignature: String {
        outstanding.map { "\($0.id)|\($0.total)|\($0.currency ?? "")" }
            .joined(separator: ",") + "→" + currencyCode
    }

    private func recalculateOutstanding() async {
        let target = currencyCode
        var sum = 0.0
        var counted = 0
        var converted = false

        for quote in outstanding {
            let code = quote.currency ?? target
            if code == target {
                sum += quote.total
                counted += 1
            } else if let rate = try? await FXService.rate(from: code, to: target) {
                sum += quote.total * rate
                counted += 1
                converted = true
            }
        }

        outstandingTotal = sum
        outstandingCount = counted
        outstandingIsApproximate = converted
    }

    private var outstandingSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting on clients")
                    .font(.caption)
                    .foregroundStyle(Color(.blueAccentText))
                // Always in the user's own currency, converting quotes priced
                // in another one — a raw sum across currencies is meaningless.
                Text(outstandingLabel)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
            }
            Spacer(minLength: 8)
            Text("\(outstandingCount) quote\(outstandingCount == 1 ? "" : "s")")
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
            share(quote)
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
    /// No button of its own — the mic in the tab bar is the way in, and a second
    /// control for the same thing only splits the attention it needs.
    private var emptyState: some View {
        placeholder(
            icon: "mic.fill",
            title: "Your first quote starts here",
            message: "Describe a job out loud and Verbal turns it into a priced quote."
        ) {
            EmptyView()
        }
    }

    /// Stand-in rows for the moment before the first fetch lands. The splash
    /// stops waiting on the lists after two seconds so a slow launch still gets
    /// in, and what followed that was a blank page — which reads as an app that
    /// broke rather than one that is loading.
    private var loadingState: some View {
        VStack(spacing: 10) {
            ForEach(Array(Self.skeletonWidths.enumerated()), id: \.offset) { _, width in
                QuoteRowSkeleton(titleWidth: width)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        // One sweep travelling across the whole stack, not four in step.
        .shimmer(active: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your quotes")
    }

    /// Varied so the placeholders read as quotes rather than as a repeated tile.
    private static let skeletonWidths: [CGFloat] = [168, 124, 196, 142]

    /// Enough overshoot to feel alive, damped enough not to wobble — this fires
    /// on a list the user is reading, not on a splash screen.
    private static let pinSpring = Animation.spring(response: 0.34, dampingFraction: 0.62)

    /// Removal gets no bounce. A row leaving should close up behind itself, not
    /// spring — the quote is gone and the motion shouldn't be cheerful about it.
    static let rowRemoval = Animation.easeInOut(duration: 0.28)

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
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(.mainText))
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
            guard filter.matches(quote.effectiveStatus) else { return false }
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
            groups[QuoteStatusGroup(status: quote.effectiveStatus), default: []].append(quote)
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

    /// Load the line items (usually already prefetched by the row) before
    /// opening the share panel — without them the PDF would print an empty
    /// table, so this waits rather than rendering a half-built document.
    private func share(_ quote: QuoteSummary) {
        Task {
            await session.prefetchLineItems(for: quote.id)
            // Last chance to put a name on the document before a customer reads
            // it. Whatever they choose, the share still happens.
            if BusinessPrompt.shouldAsk(session.businessProfile) {
                shareAfterDetails = quote
            } else {
                shareTarget = quote
            }
        }
    }

    /// The quote as a printable document, for the share panel's PDF.
    private func pdfDocument(for quote: QuoteSummary) -> QuoteDocument {
        QuoteDocument(
            title: quote.displayTitle,
            number: quote.number,
            clientName: quote.clientName,
            createdAt: quote.createdAt,
            validityDate: quote.validityDate,
            jobSummary: quote.jobSummary,
            scope: quote.scope,
            lineItems: session.lineItems(for: quote.id) ?? [],
            subtotal: quote.subtotal,
            taxRate: quote.taxRate,
            taxAmount: quote.taxAmount,
            total: quote.total,
            currency: quote.currency,
            business: session.businessProfile
        )
    }

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
            // Every other mutation here animates; a row that simply blinks out
            // makes the list look like it lost its place rather than obeyed.
            withAnimation(Self.rowRemoval) { quotes.removeAll { $0.id == quote.id } }
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
        // A spring rather than the default curve. Three things move at once —
        // the pin appears, the tint comes up, and the card travels to the
        // Pinned section — and a little overshoot makes that read as the card
        // answering rather than as a list quietly re-sorting itself.
        withAnimation(Self.pinSpring) { quotes[index].pinned = newValue }
        do {
            try await QuoteService.setPinned(id: quote.id, pinned: newValue)
        } catch {
            withAnimation(Self.pinSpring) { quotes[index].pinned = quote.pinned }
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
                            // Springs in from nothing at the corner it will
                            // occupy, so the pin reads as being pressed into
                            // the card rather than fading onto it.
                            .transition(
                                .scale(scale: 0.1, anchor: .bottomLeading)
                                    .combined(with: .opacity)
                            )
                    }
                    Text(quote.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                }
                // Lead with the client when there is one — job titles repeat
                // ("Bathroom re-tiling" three times over), names don't.
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    /// Client name when known, otherwise when the quote was made. The client is
    /// the more useful identifier — several quotes share the same job title.
    private var subtitle: String {
        let age = quote.createdAt.formatted(.relative(presentation: .named))
        guard let client = quote.clientName, !client.isEmpty else { return age }
        return "\(client) · \(age)"
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
        switch quote.effectiveStatus {
        case "draft": return "Draft"
        case "sent": return "Sent"
        case "viewed": return "Viewed"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "expired": return "Expired"
        default: return quote.effectiveStatus.capitalized
        }
    }

    private var pillForeground: Color {
        switch quote.effectiveStatus {
        case "draft": return .orange
        case "viewed": return Color(.blueAccentText)
        case "accepted": return .green
        case "declined": return .red
        case "expired": return .secondary
        default: return Color(.blueAccentText)
        }
    }

    private var pillBackground: Color {
        switch quote.effectiveStatus {
        case "draft": return .orange.opacity(0.14)
        case "viewed": return Color(.royalBlue50)
        case "accepted": return .green.opacity(0.14)
        case "declined": return .red.opacity(0.12)
        case "expired": return Color(.separator).opacity(0.5)
        default: return Color(.royalBlue25)
        }
    }
}

// MARK: - Loading placeholder

/// A quote card with its content replaced by bars. Deliberately built to
/// `QuoteRow`'s geometry — same radius, padding, border and column positions —
/// so the real cards land where the placeholders were instead of shifting the
/// page as they arrive.
private struct QuoteRowSkeleton: View {
    let titleWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                bar(titleWidth, 15)
                bar(titleWidth * 0.55, 11)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                bar(62, 13)
                bar(52, 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private func bar(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
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
