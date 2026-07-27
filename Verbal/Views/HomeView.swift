//
//  HomeView.swift
//  Verbal
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Binding var showCreate: Bool
    @State private var quotes: [QuoteSummary] = []
    @State private var isLoading = false
    @State private var filter: QuoteFilter = .all

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
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
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
                    NavigationLink {
                        ProfileView()
                    } label: {
                        AvatarView(image: session.avatarImage, urlString: session.profile?.avatarUrl, size: 30)
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                QuoteRecordingView()
                    .environment(session)
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
        let filtered = quotes.filter { filter.matches($0.status) }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text?.isEmpty == false ? text! : "No transcript saved.")
                    .font(.callout)
                    .foregroundStyle(text?.isEmpty == false ? Color(.mainText) : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(Color(.mainBackground))
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
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

    private var missingCount: Int { lineItems.filter(\.isMissingPrice).count }

    private var shareText: String {
        var lines = [quote.displayTitle]
        if let summary = quote.jobSummary, !summary.isEmpty { lines.append(summary) }
        return lines.joined(separator: "\n")
    }

    private var chips: some View {
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
            // 3. Status (my pick).
            QuoteChip(text: statusLabel) {
                Image(systemName: statusIcon)
            }
        }
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

    private var statusLabel: String {
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

    private var statusIcon: String {
        switch quote.status {
        case "draft": return "pencil"
        case "sent": return "paperplane"
        case "viewed": return "eye"
        case "accepted": return "checkmark.circle"
        case "declined": return "xmark.circle"
        case "expired": return "clock.badge.exclamationmark"
        default: return "circle"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(quote.displayTitle)
                    .font(.robotoSlab(34, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(2)

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
                    Text(quote.displayTitle)
                        .font(.robotoSlab(17, relativeTo: .headline))
                        .foregroundStyle(Color(.mainText))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
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
