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
    @State private var isLoading = false
    @State private var filter: QuoteFilter = .all
    @State private var shareTarget: QuoteSummary?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if quotes.isEmpty {
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
                                subtitle: "Total \(quote.total.formatted(.number.precision(.fractionLength(2)))) · \(quote.status.capitalized)",
                                shareText: shareText(for: quote)) {
                    Task { await markSent(quote) }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: - List

    private var quotesList: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.quotes) { quote in
                        NavigationLink {
                            QuoteDetailView(quote: quote) {
                                quotes.removeAll { $0.id == quote.id }
                            }
                            .environment(session)
                        } label: {
                            QuoteRow(quote: quote)
                        }
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await delete(quote) }
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
                } header: {
                    Text(section.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
        } catch {
            // Leave the row in place if the delete failed.
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
        var groups: [QuoteStatusGroup: [QuoteSummary]] = [:]
        for quote in filtered {
            groups[QuoteStatusGroup(status: quote.status), default: []].append(quote)
        }
        return QuoteStatusGroup.allCases.compactMap { group in
            guard let items = groups[group], !items.isEmpty else { return nil }
            return ("\(group.title) · \(items.count)", items)
        }
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
            .background(Color(.mainBackground))
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
        VStack(alignment: .leading, spacing: 3) {
            Text(quote.displayTitle)
                .font(.headline)
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
            Text(quote.createdAt, format: .relative(presentation: .named))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
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
    /// Live status — editable via the status chip menu, persisted to Supabase.
    @State private var status: String

    /// Statuses offered in the status-chip menu, in workflow order.
    private let selectableStatuses = ["draft", "sent", "viewed", "accepted", "declined", "expired"]

    init(quote: QuoteSummary, onDeleted: @escaping () -> Void) {
        self.quote = quote
        self.onDeleted = onDeleted
        _status = State(initialValue: quote.status)
    }

    private var missingCount: Int { lineItems.filter(\.isMissingPrice).count }

    private var shareText: String {
        var lines = [quote.displayTitle]
        if let summary = quote.jobSummary, !summary.isEmpty { lines.append(summary) }
        return lines.joined(separator: "\n")
    }

    private var shareSubtitle: String {
        let total = quote.total.formatted(.number.precision(.fractionLength(2)))
        return "Total \(total) · \(statusLabel)"
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
                // 3. Status — tap to change it.
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
                        lineTotal: item.lineTotal
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
                    Text(quote.total, format: .number.precision(.fractionLength(2)))
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
        .background(Color(.mainBackground))
        .task {
            lineItems = (try? await QuoteService.fetchLineItems(quoteId: quote.id)) ?? []
            transcriptText = (try? await QuoteService.fetchTranscript(quoteId: quote.id)) ?? nil
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
                    Text("Share").fontWeight(.semibold)
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
                        Task {
                            try? await QuoteService.deleteQuote(id: quote.id)
                            onDeleted()
                            dismiss()
                        }
                    } label: {
                        Label("Delete quote", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}
