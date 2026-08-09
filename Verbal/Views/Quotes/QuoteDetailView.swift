//
//  QuoteDetailView.swift
//  Verbal
//
//  The quote review screen: header, chips (creator / date / currency / status),
//  job summary, and the line-item table with a computed total.
//

import SwiftUI
import UIKit

struct QuoteDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let quote: QuoteSummary
    var onDeleted: () -> Void
    /// Lets the list behind this screen show the new name straight away. Home
    /// keeps its own copy of the rows and only refetches on its own schedule,
    /// so without this a rename doesn't reach the list you came from.
    var onRenamed: (String?) -> Void = { _ in }
    /// Same reason as `onRenamed`: the list holds its own rows, and a pin has
    /// to move the card into the Pinned section behind this screen.
    var onPinChanged: (Bool) -> Void = { _ in }
    /// For changes the list can't be handed directly — a duplicate is a row it
    /// knows nothing about, and edited line items change a total it holds a
    /// stale copy of. Both mean: refetch.
    var onNeedsRefresh: () -> Void = { }
    @State private var showHeaderTitle = false
    @State private var lineItems: [QuoteLineItem]
    @State private var transcriptText: String?
    /// The fetch failed and nothing was cached, so the sheet should say the
    /// transcript can't be reached rather than that it doesn't exist.
    @State private var transcriptUnreachable = false
    @State private var showTranscript = false
    /// Renaming, and the field's contents while the alert is up. Seeded from
    /// the current name each time it opens, so an abandoned edit doesn't come
    /// back the next time.
    @State private var showRename = false
    @State private var renameText = ""
    @State private var toast: Toast?
    @State private var pinned: Bool
    @State private var showDuplicateConfirm = false
    @State private var showShare = false
    /// Collects business details before the first share, when there are none.
    @State private var showBusinessDetails = false
    /// Confirms sending a quote that still has gaps in it.
    @State private var showUnpricedWarning = false
    /// Confirms sending a fully priced quote that isn't addressed to anyone.
    @State private var showNoClientWarning = false

    /// Ask for business details first if the document would go out unheaded,
    /// then warn about gaps, then share. Each step is skipped when it has
    /// nothing to say, so the common case is still one tap.
    private func beginShare() {
        if BusinessPrompt.shouldAsk(session.businessProfile) {
            showBusinessDetails = true
        } else if missingCount > 0 {
            showUnpricedWarning = true
        } else {
            shareOrAskForClient()
        }
    }

    /// The last gate before sharing. A quote with every price on it and no name
    /// at the top is a document the customer can't tell was written for them,
    /// and it's the one detail the transcript often doesn't carry.
    ///
    /// Reached after the unpriced warning as well as instead of it, so a quote
    /// missing both is asked about both rather than having the second silently
    /// waived by answering the first.
    private func shareOrAskForClient() {
        if clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showNoClientWarning = true
        } else {
            showShare = true
        }
    }

    private var unpricedTitle: String {
        "Share with \(missingCount) item\(missingCount == 1 ? "" : "s") unpriced?"
    }
    @State private var showEdit = false
    @State private var showLineItems = false
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

    init(quote: QuoteSummary, initialLineItems: [QuoteLineItem] = [],
         onDeleted: @escaping () -> Void,
         onRenamed: @escaping (String?) -> Void = { _ in },
         onPinChanged: @escaping (Bool) -> Void = { _ in },
         onNeedsRefresh: @escaping () -> Void = { }) {
        self.quote = quote
        self.onDeleted = onDeleted
        self.onRenamed = onRenamed
        self.onPinChanged = onPinChanged
        self.onNeedsRefresh = onNeedsRefresh
        _pinned = State(initialValue: quote.pinned)
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
                // 5. How long the price holds — tap to move it. Until this was
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
                // 6. Reference number, assigned when the quote was created.
                // Last on purpose: it is the only chip here that can't be
                // tapped or changed, and a reference nobody reads until
                // they quote it back to you doesn't belong in front of the
                // things the user actually adjusts.
                if let numberLabel = quote.numberLabel {
                    QuoteChip(text: numberLabel) {
                        Image(systemName: "number")
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    @ViewBuilder
    /// A titled panel with its own header bar, after the code blocks in Claude:
    /// a quiet label on the left and the control that opens it on the right.
    /// The heading used to float above a bordered list, which named the section
    /// but gave it nothing to be tapped by — editing was somewhere else
    /// entirely, inside a form about the quote's wording.
    private var lineItemsSection: some View {
        if !lineItems.isEmpty {
            LineItemsCard(onExpand: { showLineItems = true }) {
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
        // Kept in line with the content scrolling above it, so the total sits
        // under the prices rather than inset from them.
        .padding(.horizontal, 20)
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
            business: session.businessProfile,
            logo: session.businessLogo
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

    /// Copy the quote and stay put. Following the new draft would take someone
    /// away from what they were reading to a screen identical to it; the copy
    /// is waiting on the list when they go back.
    private func duplicateQuote() {
        Task {
            do {
                try await QuoteService.duplicateQuote(id: quote.id)
                onNeedsRefresh()
                toast = Toast(style: .success, message: "Copy saved as a draft")
            } catch {
                toast = Toast(style: .error, message: "Couldn't duplicate this quote")
            }
        }
    }

    /// Optimistic like the rest, and reported back so the card moves into the
    /// Pinned section on the list behind this screen.
    private func togglePin() {
        let newValue = !pinned
        // Fired with the optimistic update, not after the round trip, so the
        // tap answers immediately.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pinned = newValue
        onPinChanged(newValue)
        Task {
            do {
                try await QuoteService.setPinned(id: quote.id, pinned: newValue)
            } catch {
                pinned = !newValue
                onPinChanged(!newValue)
                toast = Toast(style: .error,
                              message: newValue ? "Couldn't pin this quote"
                                                : "Couldn't unpin this quote")
            }
        }
    }

    /// Optimistic, like the status and pin changes: the new name is on screen
    /// before the write lands, and put back if it doesn't.
    private func rename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing typed is a slip, not an instruction to strip the name off a
        // quote — leave it as it was.
        guard !trimmed.isEmpty, trimmed != title else { return }
        let previous = title
        withAnimation(.easeInOut(duration: 0.2)) { title = trimmed }
        onRenamed(trimmed)
        Task {
            do {
                try await QuoteService.setTitle(quoteId: quote.id, title: trimmed)
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) { title = previous }
                onRenamed(previous)
                toast = Toast(style: .error, message: "Couldn't rename this quote")
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
                    VStack(alignment: .leading, spacing: 8) {
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

                // 4 on top of the stack's own 20. A section still starts a step
                // away from the one before it — 24 against the 8 under a heading
                // — but the blocks stay close enough to read as one document.
                ScopeList(items: scope)
                    .padding(.top, 4)

                lineItemsSection
                    .padding(.top, 4)
            }
            // 20, matching Home and the rate card. A quote opened from the list
            // used to step 4pt inward from the row that was tapped.
            .padding(.horizontal, 20)
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
        }
        // Its own task, so the disk read isn't queued behind the line-item
        // request above. Sharing one meant the transcript waited for that
        // fetch to finish — offline, for it to time out — which is why the
        // text arrived seconds late while the quote itself was instant.
        .task {
            // Before the first await, so it lands with the first frame. Disk
            // first, network second, the same order the quote list uses.
            transcriptText = QuoteService.cachedTranscript(quoteId: quote.id)
            do {
                // A successful reply saying there is none is an answer, so it
                // replaces the cached copy rather than being ignored.
                transcriptText = try await QuoteService.fetchTranscript(quoteId: quote.id)
                transcriptUnreachable = false
            } catch {
                // Unreachable, not absent. Keep what's on disk — and only call
                // it unreachable if there was nothing there to keep.
                transcriptUnreachable = transcriptText == nil
            }
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
            TranscriptSheet(text: transcriptText, unreachable: transcriptUnreachable)
        }
        .sheet(isPresented: $showEdit) {
            EditQuoteView(quoteId: quote.id,
                          title: title,
                          jobSummary: jobSummary,
                          scope: scope) { newSummary, newScope in
                jobSummary = newSummary
                scope = newScope
            }
        }
        .sheet(isPresented: $showLineItems) {
            LineItemsSheet(quoteId: quote.id,
                           currency: currency,
                           taxRate: quote.taxRate,
                           lineItems: lineItems) { _, newTotal in
                total = newTotal
                // Refetched rather than handed back: items added in the sheet
                // have no server id until they're inserted, and the rows here
                // are keyed by it.
                Task {
                    lineItems = (try? await QuoteService.fetchLineItems(quoteId: quote.id)) ?? lineItems
                }
                // The list's copy of this quote still holds the old total.
                onNeedsRefresh()
            }
        }
        .sheet(isPresented: $showBusinessDetails) {
            BusinessDetailsSheet {
                // Hand over after this one has closed — to the warning if there
                // is one to give, otherwise straight to the share panel.
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    if missingCount > 0 { showUnpricedWarning = true } else { shareOrAskForClient() }
                }
            }
            .environment(session)
        }
        // A warning, never a block. A price the supplier hasn't given yet is a
        // normal thing to send as TBC — the quote just shouldn't leave without
        // the user knowing it has holes in it.
        .alert(unpricedTitle, isPresented: $showUnpricedWarning) {
            // Onto the client question rather than straight out, after a beat:
            // one alert cannot replace another in the same breath, the same
            // reason the business sheet hands over on a delay.
            Button("Share anyway") {
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    shareOrAskForClient()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll print as “TBC” and the total won't include them.")
        }
        // The same shape as the warning above it: a question, a plain action,
        // and Cancel. Cancel is the useful half — it puts them back on the
        // screen with the client chip at the top of it.
        .alert("Share without a client?", isPresented: $showNoClientWarning) {
            Button("Share anyway") { showShare = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The quote will go out with no name on it. Add one from the chip at the top.")
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
                    // A ControlGroup inside a Menu is what gives Notes and
                    // Photos that row of icons across the top — the system
                    // draws it, so it matches whatever the OS does next.
                    //
                    // What earns a place here: acting on the quote and handing
                    // the screen straight back. The items below it all open
                    // something instead, which is why they stay a list.
                    ControlGroup {
                        Button {
                            togglePin()
                        } label: {
                            Label(pinned ? "Unpin" : "Pin",
                                  systemImage: pinned ? "pin.slash" : "pin")
                        }
                        Button {
                            showDuplicateConfirm = true
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button {
                            // Seeded with what's on screen, including the
                            // summary standing in for a quote that was never
                            // named — the field should open on the name being
                            // changed.
                            renameText = displayTitle
                            showRename = true
                        } label: {
                            Label("Rename", systemImage: "character.cursor.ibeam")
                        }
                    }
                    Divider()
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
        .alert("Duplicate this quote?", isPresented: $showDuplicateConfirm) {
            Button("Duplicate") { duplicateQuote() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This creates a copy of “\(displayTitle)” as a new draft.")
        }
        .alert("Rename quote", isPresented: $showRename) {
            TextField("Quote name", text: $renameText)
                .textInputAutocapitalization(.sentences)
            Button("Save") { rename() }
            Button("Cancel", role: .cancel) {}
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
        .toast($toast)
    }
}
