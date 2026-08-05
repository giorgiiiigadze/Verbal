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
    /// Collects business details before the first share, when there are none.
    @State private var showBusinessDetails = false
    /// Confirms sending a quote that still has gaps in it.
    @State private var showUnpricedWarning = false

    /// Ask for business details first if the document would go out unheaded,
    /// then warn about gaps, then share. Each step is skipped when it has
    /// nothing to say, so the common case is still one tap.
    private func beginShare() {
        if BusinessPrompt.shouldAsk(session.businessProfile) {
            showBusinessDetails = true
        } else if missingCount > 0 {
            showUnpricedWarning = true
        } else {
            showShare = true
        }
    }

    private var unpricedTitle: String {
        "Share with \(missingCount) item\(missingCount == 1 ? "" : "s") unpriced?"
    }
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showClientSheet = false
    /// Seeded from the quote and kept in sync after an edit, so the chip
    /// updates without refetching the list.
    @State private var clientName: String
    /// Live title, summary & scope — editable via the edit sheet.
    @State private var title: String
    @State private var jobSummary: String
    @State private var scope: [String]
    /// Live status — editable via the status chip menu, persisted to Supabase.
    @State private var status: String
    /// Live validity — editable via the validity chip, persisted to Supabase.
    @State private var validityDate: Date?
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
        // The status as the list shows it, so a quote filed under Expired there
        // doesn't call itself Sent the moment it's opened.
        _status = State(initialValue: quote.effectiveStatus)
        _validityDate = State(initialValue: quote.validityDate)
        _currency = State(initialValue: quote.currency ?? AppCurrency.current.rawValue)
        _total = State(initialValue: quote.total)
        _title = State(initialValue: quote.title ?? "")
        _jobSummary = State(initialValue: quote.jobSummary ?? "")
        _scope = State(initialValue: quote.scope)
        _clientName = State(initialValue: quote.clientName ?? "")
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
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                // 1. Who it's for — tap to name or change the client.
                Button { showClientSheet = true } label: {
                    QuoteChip(text: clientName.isEmpty ? "Add client" : clientName,
                              tinted: clientName.isEmpty) {
                        Image(systemName: clientName.isEmpty ? "person.badge.plus" : "person.fill")
                    }
                }
                .buttonStyle(.plain)
                // 2. Reference number, assigned when the quote was created.
                if let numberLabel = quote.numberLabel {
                    QuoteChip(text: numberLabel) {
                        Image(systemName: "number")
                    }
                }
                // 3. Creation date.
                QuoteChip(text: dateLabel) {
                    Image(systemName: "calendar")
                }
                // 4. How long the price holds — tap to move it. Until this was
                // editable an expired quote could not be revived at all: the
                // date was set once at creation and nothing could reach it, so
                // extending an offer meant duplicating the quote.
                Menu {
                    ForEach(Self.validityExtensions, id: \.days) { option in
                        Button {
                            changeValidity(toDaysFromToday: option.days)
                        } label: {
                            Label(option.label, systemImage: "clock.arrow.circlepath")
                        }
                    }
                } label: {
                    QuoteChip(text: validityLabel, tinted: isPastValidity) {
                        Image(systemName: isPastValidity
                              ? "clock.badge.exclamationmark" : "clock")
                    }
                }
                .buttonStyle(.plain)
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
        .scrollIndicators(.hidden)
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

    /// The quote as a printable document, built from the live edited values so
    /// the PDF matches what's on screen rather than the last fetch.
    private var pdfDocument: QuoteDocument {
        // Mirror the database's arithmetic on the live line items, so an edit
        // made in this session prints the right tax without a refetch.
        let subtotal = lineItems.compactMap(\.lineTotal).reduce(0, +)
        let tax = (subtotal * quote.taxRate / 100).roundedToCents
        return QuoteDocument(
            title: displayTitle,
            number: quote.number,
            clientName: clientName.isEmpty ? nil : clientName,
            createdAt: quote.createdAt,
            validityDate: validityDate,
            jobSummary: jobSummary.isEmpty ? nil : jobSummary,
            scope: scope,
            lineItems: lineItems,
            subtotal: subtotal,
            taxRate: quote.taxRate,
            taxAmount: tax,
            total: (subtotal + tax).roundedToCents,
            currency: currency,
            business: session.businessProfile
        )
    }

    private var dateLabel: String { quoteDateLabel(quote.createdAt) }

    /// "Valid to 14 Aug 2026" while it still holds, "Expired 2 Aug 2026" after.
    private var validityLabel: String {
        guard let validityDate else { return "Add validity" }
        let day = QuoteDateFormat.display(validityDate)
        return isPastValidity ? "Expired \(day)" : "Valid to \(day)"
    }

    /// Read from the live date so extending a quote un-expires it immediately,
    /// rather than after a refetch.
    private var isPastValidity: Bool {
        guard let validityDate else { return false }
        return validityDate < Calendar.current.startOfDay(for: Date())
    }

    /// Offered from the chip. All relative to today, because the reason to
    /// touch this is almost always "give them another couple of weeks".
    private static let validityExtensions: [(days: Int, label: String)] = [
        (7, "1 week from today"),
        (14, "2 weeks from today"),
        (30, "30 days from today"),
        (60, "60 days from today")
    ]

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
    private func changeValidity(toDaysFromToday days: Int) {
        let calendar = Calendar.current
        guard let newDate = calendar.date(byAdding: .day, value: days,
                                          to: calendar.startOfDay(for: Date())) else { return }
        let previousDate = validityDate
        let previousStatus = status

        withAnimation(.easeInOut(duration: 0.2)) {
            validityDate = newDate
            // Extending revives a quote the list had filed under Expired, and
            // that was only ever a reading of the date — so the status chip has
            // to stop saying it. The stored column is what it reverts to.
            if status == "expired", quote.status != "expired" {
                status = quote.status
            }
        }

        Task {
            do {
                try await QuoteService.updateValidityDate(id: quote.id, date: newDate)
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    validityDate = previousDate
                    status = previousStatus
                }
            }
        }
    }

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
                    .padding(.top, 8)

                lineItemsSection
                    .padding(.top, 8)
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
            } else if lineItems.isEmpty {
                // Offline, and this quote was opened before its row had a
                // chance to prefetch. Ask the store, which falls back to disk.
                await session.prefetchLineItems(for: quote.id)
                if let stored = session.lineItems(for: quote.id) { lineItems = stored }
            }
            transcriptText = (try? await QuoteService.fetchTranscript(quoteId: quote.id)) ?? nil
        }
        .task {
            // Warm the exchange-rate cache so a conversion opens instantly.
            await FXService.prefetch(base: currency)
        }
        .sheet(isPresented: $showClientSheet) {
            ClientSheet(name: $clientName)
        }
        .onChange(of: clientName) { previous, current in
            // Persist only real edits, not the initial seed.
            guard previous != current else { return }
            Task { try? await QuoteService.setClient(quoteId: quote.id, name: current) }
        }
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(text: transcriptText)
        }
        .sheet(isPresented: $showEdit) {
            EditQuoteView(quoteId: quote.id,
                          currency: currency,
                          taxRate: quote.taxRate,
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
        .sheet(isPresented: $showBusinessDetails) {
            BusinessDetailsSheet {
                // Hand over after this one has closed — to the warning if there
                // is one to give, otherwise straight to the share panel.
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    if missingCount > 0 { showUnpricedWarning = true } else { showShare = true }
                }
            }
            .environment(session)
        }
        // A warning, never a block. A price the supplier hasn't given yet is a
        // normal thing to send as TBC — the quote just shouldn't leave without
        // the user knowing it has holes in it.
        .alert(unpricedTitle, isPresented: $showUnpricedWarning) {
            Button("Share anyway") { showShare = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll print as “TBC” and the total won't include them.")
        }
        .sheet(isPresented: $showShare) {
            ShareQuotePanel(title: displayTitle,
                            subtitle: shareSubtitle,
                            shareText: shareText,
                            document: pdfDocument) {
                // Sharing a draft marks it as Sent (don't downgrade later statuses).
                if status == "draft" { changeStatus(to: "sent") }
            }
        }
        .sheet(item: $pendingCurrency) { target in
            ConvertCurrencySheet(quoteID: quote.id,
                                 lineItems: lineItems,
                                 currentTotal: total,
                                 taxRate: quote.taxRate,
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
                    beginShare()
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
