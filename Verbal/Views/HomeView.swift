//
//  HomeView.swift
//  Verbal
//

import SwiftUI
import UIKit

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

    var body: some View {
        NavigationStack {
            Group {
                if quotes.isEmpty && !hasLoaded {
                    // Still loading first paint — stay blank, not "no quotes".
                    Color(.homeBackground)
                } else if quotes.isEmpty {
                    emptyState
                } else {
                    quotesList
                }
            }
            .background(Color(.homeBackground))
            .navigationTitle("Your quotes")
            .searchable(text: $searchText, prompt: "Search quotes")
            .searchToolbarBehavior(.minimize)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                QuoteRecordingView()
                    .environment(session)
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
    }

    // MARK: - List

    private var quotesList: some View {
        List {
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
                            // default trailing chevron (we draw our own inside).
                            NavigationLink {
                                QuoteDetailView(quote: quote) {
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Your quotes appear here..")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func shareText(for quote: QuoteSummary) -> String {
        var lines = [quote.displayTitle]
        if let summary = quote.jobSummary, !summary.isEmpty { lines.append(summary) }
        return lines.joined(separator: "\n")
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            quotes = try await QuoteService.fetchQuotes()
        } catch {
            // Keep whatever we had; a toast/list-error can be added later.
        }
        hasLoaded = true
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

    /// Quotes grouped into status sections, honoring the active filter.
    /// Section titles include a count, e.g. "Waiting to hear back · 2".
    private var sections: [(title: String, quotes: [QuoteSummary])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
}

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

/// Sheet showing the raw transcript a quote was generated from.
struct TranscriptSheet: View {
    let text: String?
    /// When provided, the transcript is editable in place and an Edit button appears.
    var editable: Binding<String>?
    /// When provided, a Regenerate button appears that re-runs the AI on the transcript.
    var onRegenerate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @FocusState private var editorFocused: Bool

    private var displayText: String { editable?.wrappedValue ?? text ?? "" }
    private var hasText: Bool { !displayText.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcript")
                            .font(.robotoSlab(34, relativeTo: .largeTitle))
                            .foregroundStyle(Color(.mainText))
                        Text("Review or share the full transcript.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if isEditing, let editable {
                        TextField("Transcript", text: editable, axis: .vertical)
                            .font(.callout)
                            .foregroundStyle(Color(.mainText))
                            .focused($editorFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(hasText ? displayText : "No transcript saved.")
                            .font(.callout)
                            .foregroundStyle(hasText ? Color(.mainText) : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    actionBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .background(Color(.homeBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: displayText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(!hasText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = displayText
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(!hasText)

            if editable != nil {
                Button {
                    isEditing.toggle()
                    editorFocused = isEditing
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "pencil")
                }
            }

            if let onRegenerate {
                Button {
                    dismiss()
                    onRegenerate()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(!hasText)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color(.mainText))
        .padding(.top, 4)
    }
}

/// Verbal's custom share panel for a quote — a preview plus Share / Copy actions.
struct ShareQuotePanel: View {
    let title: String
    let subtitle: String
    let shareText: String
    /// Called when the quote is actually shared or copied (used to mark it Sent).
    var onShared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Share quote")
                    .font(.robotoSlab(22, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))
                Spacer()
                Button(role: .close) { dismiss() }
            }

            // Quote preview.
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.royalBlue100))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color(.royalBlue600))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            // Actions.
            HStack(spacing: 12) {
                actionButton(title: "Share via…", systemImage: "square.and.arrow.up") {
                    showSystemShare = true
                }
                actionButton(title: copied ? "Copied" : "Copy",
                             systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = shareText
                    withAnimation { copied = true }
                    onShared()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: [shareText]) { completed in
                if completed {
                    onShared()
                    dismiss()
                }
            }
        }
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title).fontWeight(.medium)
            }
            .foregroundStyle(Color(.mainText))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// UIActivityViewController wrapper that reports whether the share completed,
/// so callers can react (e.g. marking a quote as Sent).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Small native rounded-rectangle chip with a leading icon/avatar and text.
struct QuoteChip<Leading: View>: View {
    let text: String
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
                .font(.body)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.surface), in: .capsule)
    }
}

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
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Placeholder detail — to be built out into the quote review/edit screen.
private struct QuoteDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let quote: QuoteSummary
    var onDeleted: () -> Void
    @State private var showHeaderTitle = false
    @State private var lineItems: [QuoteLineItem] = []
    @State private var transcriptText: String?
    @State private var showTranscript = false
    @State private var showShare = false
    @State private var showDeleteConfirm = false
    /// Live status — editable via the status chip menu, persisted to Supabase.
    @State private var status: String
    /// Live currency — editable via the currency chip, persisted to Supabase.
    @State private var currency: String
    /// Live total — updated when the quote is converted to another currency.
    @State private var total: Double
    /// Currency the user picked in the chip, pending the convert/relabel choice.
    @State private var pendingCurrency: CurrencyTarget?

    /// Identifiable wrapper so a picked currency code can drive `.sheet(item:)`.
    private struct CurrencyTarget: Identifiable { let id: String }

    /// Statuses offered in the status-chip menu, in workflow order.
    private let selectableStatuses = ["draft", "sent", "viewed", "accepted", "declined", "expired"]

    init(quote: QuoteSummary, onDeleted: @escaping () -> Void) {
        self.quote = quote
        self.onDeleted = onDeleted
        _status = State(initialValue: quote.status)
        _currency = State(initialValue: quote.currency ?? AppCurrency.current.rawValue)
        _total = State(initialValue: quote.total)
    }

    private var missingCount: Int { lineItems.filter(\.isMissingPrice).count }

    private var shareText: String {
        var lines = [quote.displayTitle]
        if let summary = quote.jobSummary, !summary.isEmpty { lines.append(summary) }
        return lines.joined(separator: "\n")
    }

    private var shareSubtitle: String {
        let totalText = AppCurrency.format(total, code: currency)
        return "Total \(totalText) · \(statusLabel)"
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // 1. Who made the quote + their avatar.
                QuoteChip(text: creatorName) {
                    AvatarView(image: session.avatarImage,
                               urlString: session.profile?.avatarUrl,
                               size: 22)
                }
                // 2. Creation date.
                QuoteChip(text: dateLabel) {
                    Image(systemName: "calendar")
                }
                // 3. Currency — tap to change this quote's currency.
                Menu {
                    Picker("Currency", selection: Binding(
                        get: { currency },
                        set: { pendingCurrency = ($0 == currency) ? nil : CurrencyTarget(id: $0) }
                    )) {
                        ForEach(AppCurrency.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                } label: {
                    QuoteChip(text: currencyLabel) {
                        Image(systemName: "coloncurrencysign.circle")
                    }
                }
                .buttonStyle(.plain)
                // 4. Status — tap to change it.
                Menu {
                    Picker("Status", selection: Binding(
                        get: { status },
                        set: { changeStatus(to: $0) }
                    )) {
                        ForEach(selectableStatuses, id: \.self) { option in
                            Label(statusLabel(for: option),
                                  systemImage: statusIcon(for: option))
                                .tag(option)
                        }
                    }
                } label: {
                    QuoteChip(text: statusLabel) {
                        Image(systemName: statusIcon)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var lineItemsSection: some View {
        if !lineItems.isEmpty {
            VStack(spacing: 0) {
                ForEach(lineItems) { item in
                    LineItemRow(
                        description: item.description ?? "Item",
                        quantityText: item.quantityText,
                        isMissingPrice: item.isMissingPrice,
                        lineTotal: item.lineTotal,
                        currencyCode: currency
                    )
                    if item.id != lineItems.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Color(.surface), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(Color(.mainText))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(total, format: AppCurrency.format(code: currency))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    if missingCount > 0 {
                        Text("excl. \(missingCount) unpriced item\(missingCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Shows only the first name so the chip stays compact.
    private var creatorName: String {
        guard let full = session.profile?.fullName, !full.isEmpty else { return "You" }
        return String(full.split(separator: " ").first ?? "")
    }

    private var dateLabel: String { quoteDateLabel(quote.createdAt) }

    private var statusLabel: String { statusLabel(for: status) }
    private var statusIcon: String { statusIcon(for: status) }

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

    /// Chip label for the current currency, e.g. "GBP (£)".
    private var currencyLabel: String {
        let c = AppCurrency(rawValue: currency)
        return "\(currency) (\(c?.symbol ?? currency))"
    }

    /// Optimistically update the chip and persist; revert on failure.
    private func changeStatus(to newStatus: String) {
        guard newStatus != status else { return }
        let previous = status
        withAnimation(.easeInOut(duration: 0.2)) { status = newStatus }
        Task {
            do {
                try await QuoteService.updateStatus(id: quote.id, status: newStatus)
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) { status = previous }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(quote.displayTitle)
                    .font(.robotoSlab(34, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)

                chips

                if let summary = quote.jobSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(.mainText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                lineItemsSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .background(Color(.homeBackground))
        .task {
            lineItems = (try? await QuoteService.fetchLineItems(quoteId: quote.id)) ?? []
            transcriptText = (try? await QuoteService.fetchTranscript(quoteId: quote.id)) ?? nil
        }
        .task {
            // Warm the exchange-rate cache so a conversion opens instantly.
            await FXService.prefetch(base: currency)
        }
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(text: transcriptText)
        }
        .sheet(isPresented: $showShare) {
            ShareQuotePanel(title: quote.displayTitle,
                            subtitle: shareSubtitle,
                            shareText: shareText) {
                // Sharing a draft marks it as Sent (don't downgrade later statuses).
                if status == "draft" { changeStatus(to: "sent") }
            }
        }
        .sheet(item: $pendingCurrency) { target in
            ConvertCurrencySheet(quoteID: quote.id,
                                 lineItems: lineItems,
                                 currentTotal: total,
                                 fromCode: currency,
                                 toCode: target.id) { newCurrency, newTotal in
                currency = newCurrency
                if let newTotal {
                    total = newTotal
                    // Reload line items to show the converted unit prices.
                    Task { lineItems = (try? await QuoteService.fetchLineItems(quoteId: quote.id)) ?? lineItems }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 44
        } action: { _, scrolledPastTitle in
            withAnimation(.easeInOut(duration: 0.2)) {
                showHeaderTitle = scrolledPastTitle
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if showHeaderTitle {
                    MarqueeText(text: quote.displayTitle,
                                font: .robotoSlab(17, relativeTo: .headline))
                        .frame(maxWidth: 220)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShare = true
                } label: {
                    Text("Share")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(.royalBlue600))
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showTranscript = true
                    } label: {
                        Label("View transcript", systemImage: "text.quote")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete quote", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("Delete this quote?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await QuoteService.deleteQuote(id: quote.id)
                    onDeleted()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes “\(quote.displayTitle)” and its line items. This can't be undone.")
        }
    }
}
