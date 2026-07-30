//
//  QuoteDetailView.swift
//  Verbal
//
//  The quote review screen: header, chips (creator / date / currency / status),
//  job summary, and the line-item table with a computed total.
//

import SwiftUI

struct QuoteDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let quote: QuoteSummary
    var onDeleted: () -> Void
    @State private var showHeaderTitle = false
    @State private var lineItems: [QuoteLineItem]
    @State private var transcriptText: String?
    @State private var showTranscript = false
    @State private var showShare = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    /// Live title, summary & scope — editable via the edit sheet.
    @State private var title: String
    @State private var jobSummary: String
    @State private var scope: [String]
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

    init(quote: QuoteSummary, initialLineItems: [QuoteLineItem] = [], onDeleted: @escaping () -> Void) {
        self.quote = quote
        self.onDeleted = onDeleted
        _status = State(initialValue: quote.status)
        _currency = State(initialValue: quote.currency ?? AppCurrency.current.rawValue)
        _total = State(initialValue: quote.total)
        _title = State(initialValue: quote.title ?? "")
        _jobSummary = State(initialValue: quote.jobSummary ?? "")
        _scope = State(initialValue: quote.scope)
        // Seed from the prefetched cache so the line items render on first paint
        // instead of popping in after the fetch.
        _lineItems = State(initialValue: initialLineItems)
    }

    /// Title with the same fallback logic as `QuoteSummary.displayTitle`, but
    /// driven by the live editable `title`/`jobSummary`.
    private var displayTitle: String {
        if !title.isEmpty { return title }
        if !jobSummary.isEmpty { return jobSummary }
        return "Untitled quote"
    }

    private var missingCount: Int { lineItems.filter(\.isMissingPrice).count }

    private var shareText: String {
        var lines = [displayTitle]
        if !jobSummary.isEmpty { lines.append(jobSummary) }
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Line items")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
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
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
            }
        }
    }

    /// The quote's total, pinned to the bottom of the screen like a native bar.
    private var totalBar: some View {
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
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
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
                Text(displayTitle)
                    .font(.robotoSlab(34, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)

                chips

                if !jobSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Summary")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(.mainText))
                        Text(jobSummary)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(.mainText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ScopeList(items: scope)
                    .padding(.top, 20)

                lineItemsSection
                    .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .background(Color(.homeBackground))
        .safeAreaInset(edge: .bottom) {
            totalBar
        }
        .task {
            // Refresh line items in the background (kept if the refetch fails so
            // the seeded, prefetched copy stays on screen).
            if let fresh = try? await QuoteService.fetchLineItems(quoteId: quote.id) {
                lineItems = fresh
                session.cacheLineItems(fresh, for: quote.id)
            }
            transcriptText = (try? await QuoteService.fetchTranscript(quoteId: quote.id)) ?? nil
        }
        .task {
            // Warm the exchange-rate cache so a conversion opens instantly.
            await FXService.prefetch(base: currency)
        }
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(text: transcriptText)
        }
        .sheet(isPresented: $showEdit) {
            EditQuoteView(quoteId: quote.id,
                          currency: currency,
                          title: title,
                          jobSummary: jobSummary,
                          scope: scope,
                          lineItems: lineItems) { newTitle, newSummary, newScope, newTotal in
                title = newTitle
                jobSummary = newSummary
                scope = newScope
                total = newTotal
                // Reload items so descriptions/prices/order reflect the edits.
                Task { lineItems = (try? await QuoteService.fetchLineItems(quoteId: quote.id)) ?? lineItems }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareQuotePanel(title: displayTitle,
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
                    MarqueeText(text: displayTitle,
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
                        showEdit = true
                    } label: {
                        Label("Edit quote", systemImage: "pencil")
                    }
                    Button {
                        showTranscript = true
                    } label: {
                        Label("View transcript", systemImage: "text.quote")
                    }
                    Divider()
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
            Text("This permanently deletes “\(displayTitle)” and its line items. This can't be undone.")
        }
    }
}
