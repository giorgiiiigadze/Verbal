//
//  QuoteDetailView.swift
//  Verbal
//
//  The quote review screen: header, chips (client / date / status / currency),
//  job summary, and the line-item table with a computed total.
//

import SwiftUI
import UIKit

struct QuoteDetailView: View {
    /// Matches the primary Record action used throughout the app.
    private static let recordBlue = Color(.royalBlue600)

    @Environment(SessionStore.self) private var session
    @Environment(Store.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss
    let quote: QuoteSummary
    var onDeleted: () -> Void
    /// For changes no list can be handed directly — a duplicate is a row it
    /// knows nothing about. That means a refetch.
    ///
    /// Everything else this screen edits goes into `SessionStore.quotes`
    /// through `updateQuote`, and the screens drawn from it follow. There used
    /// to be a callback per field, which is why a status change — the one field
    /// nobody had written a callback for — was still the old one on the Clients
    /// tab.
    var onNeedsRefresh: () -> Void = { }
    @State private var showHeaderTitle = false
    @State private var lineItems: [QuoteLineItem]
    @State private var transcriptText: String?
    /// The fetch failed and nothing was cached, so the sheet should say the
    /// transcript can't be reached rather than that it doesn't exist.
    @State private var transcriptUnreachable = false
    @State private var showTranscript = false
    @State private var showPDFPreview = false
    @State private var pdfPreviewURL: URL?
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
        guard requireInternetForSharing() else { return }

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
        guard requireInternetForSharing() else { return }

        if clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showNoClientWarning = true
        } else {
            showShare = true
        }
    }

    private func requireInternetForSharing() -> Bool {
        guard network.isOnline else {
            toast = Toast(style: .error, message: "Internet required for sharing")
            return false
        }
        return true
    }

    private var unpricedTitle: String {
        "Share with \(missingCount) item\(missingCount == 1 ? "" : "s") unpriced?"
    }
    @State private var showEdit = false
    @State private var showLineItems = false
    @State private var showDeleteConfirm = false
    @State private var showClientSheet = false
    /// Loaded from the saved client record for the recipient block in the PDF.
    /// A scheduled-visit address remains a local fallback until it is saved.
    @State private var clientAddress: String?
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

    /// Kept outside the main view builder so Swift does not have to infer this
    /// sheet's closure together with every other sheet, alert and toolbar on
    /// the quote screen.
    private func currencyConversionSheet(for target: CurrencyTarget) -> some View {
        ConvertCurrencySheet(quoteID: quote.id,
                             lineItems: lineItems,
                             currentTotal: total,
                             taxRate: quote.taxRate,
                             fromCode: currency,
                             toCode: target.id) { newCurrency, newTotal in
            applyCurrencyChange(newCurrency, total: newTotal)
        }
    }

    private func applyCurrencyChange(_ newCurrency: String, total newTotal: Double?) {
        currency = newCurrency
        session.updateQuote(id: quote.id) { $0.currency = newCurrency }
        if let newTotal {
            total = newTotal
            session.updateQuote(id: quote.id) { $0.total = newTotal }
            // Reload line items to show the converted unit prices.
            Task { lineItems = (try? await QuoteService.fetchLineItems(quoteId: quote.id)) ?? lineItems }
            toast = Toast(style: .success, message: "Converted to \(newCurrency)")
        } else {
            toast = Toast(style: .success, message: "Currency set to \(newCurrency)")
        }
    }

    /// Statuses offered in the status-chip menu, in workflow order.
    private let selectableStatuses = ["draft", "sent", "viewed", "accepted", "declined", "expired"]

    init(quote: QuoteSummary, initialLineItems: [QuoteLineItem] = [],
         onDeleted: @escaping () -> Void,
         onNeedsRefresh: @escaping () -> Void = { }) {
        self.quote = quote
        self.onDeleted = onDeleted
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

    private var matchingClientVisits: [ScheduledVisit] {
        let key = clientName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        return session.visitStore.visits
            .filter { $0.clientKey.contains(key) }
            .sorted { $0.date > $1.date }
    }

    private var clientPhoneForPDF: String? {
        matchingClientVisits.compactMap { clean($0.phone) }.first
    }

    private var clientAddressForPDF: String? {
        clean(clientAddress) ?? matchingClientVisits.compactMap { clean($0.address) }.first
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

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
                        // Their own avatar once there is a name to draw it
                        // from, rather than the generic figure every client
                        // shared. It picks its colour off the name, so the
                        // chip carries the same circle the client list and
                        // their page do — identity without spending a tint the
                        // status chip beside it has the better claim to.
                        if clientName.isEmpty {
                            Image(systemName: "person.badge.plus")
                        } else {
                            InitialsAvatar(name: clientName, size: 26)
                        }
                    }
                }
                .buttonStyle(.plain)
                // 2. Creation date.
                QuoteChip(text: dateLabel) {
                    Image(systemName: "calendar")
                }
                // 3. Status — tap to change it. Ahead of the currency
                // because it is the one chip that changes over a quote's life,
                // and the only one worth checking on the way past.
                //
                // Coloured, unlike its neighbours: it carries the same pair the
                // list row's pill wears, so a quote accepted in the list is the
                // same green on its own page.
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
                    QuoteChip(text: statusLabel,
                              palette: (QuoteStatusStyle.text(status),
                                        QuoteStatusStyle.fill(status))) {
                        Image(systemName: statusIcon)
                    }
                }
                .buttonStyle(.plain)
                // 4. Currency — tap to change this quote's currency.
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
                if let numberLabel = quote.numberLabel(prefix: session.businessProfile?.quoteNumberPrefix) {
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
                        currencyCode: currency,
                        confidence: item.confidence
                    )
                    if item.id != lineItems.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    /// Match the generated-quote review exactly: the narrative reads as a
    /// document before the price table, rather than as a second card competing
    /// with it. Saved and just-generated quotes should not have two layouts.
    @ViewBuilder
    private var jobDetailsSection: some View {
        if !jobSummary.isEmpty || !scope.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                if !jobSummary.isEmpty {
                    Text(emphasizedSummary(jobSummary))
                        .foregroundStyle(Color(.mainText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ScopeList(items: scope)
                    .padding(.top, 4)
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
                // Counts to its new value when a price is edited or the
                // quote is converted — see `RollingAmount`. Monospaced digits
                // so the figure doesn't shuffle sideways while it moves.
                RollingAmount(value: total, code: currency)
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
            number: quote.numberText(prefix: session.businessProfile?.quoteNumberPrefix),
            clientName: clientName.isEmpty ? nil : clientName,
            clientAddress: clientAddressForPDF,
            clientPhone: clientPhoneForPDF,
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
                session.updateQuote(id: quote.id) { $0.status = quote.status }
            }
        }

        Task {
            do {
                try await QuoteService.updateValidityDate(id: quote.id, date: newDate)
                await QuoteExpiryNotifications.schedule(id: quote.id,
                                                        title: displayTitle,
                                                        status: status,
                                                        validityDate: newDate)
                onNeedsRefresh()
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    validityDate = previousDate
                    status = previousStatus
                    session.updateQuote(id: quote.id) { $0.status = previousStatus }
                }
            }
        }
    }

    private func changeStatus(to newStatus: String) {
        guard newStatus != status else { return }
        let previous = status
        withAnimation(.easeInOut(duration: 0.2)) {
            status = newStatus
            // Into the shared list as well as this screen's own state, so the
            // pill on Home and the client's stats change with it. The revert
            // below has to do the same, or a write the server refused is left
            // standing everywhere except here.
            session.updateQuote(id: quote.id) { $0.status = newStatus }
        }
        Task {
            do {
                try await QuoteService.updateStatus(id: quote.id, status: newStatus)
                if newStatus == "sent" || newStatus == "viewed" {
                    await QuoteExpiryNotifications.schedule(id: quote.id,
                                                            title: displayTitle,
                                                            status: newStatus,
                                                            validityDate: validityDate)
                } else {
                    QuoteExpiryNotifications.cancel(quote)
                }
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    status = previous
                    session.updateQuote(id: quote.id) { $0.status = previous }
                }
            }
        }
    }

    /// Copy the quote and stay put. Following the new draft would take someone
    /// away from what they were reading to a screen identical to it; the copy
    /// is waiting on the list when they go back.
    private func duplicateQuote() {
        guard store.canCreateQuote(remaining: session.freeQuotesRemaining) else {
            store.isPaywallPresented = true
            return
        }
        Task {
            do {
                try await QuoteService.duplicateQuote(id: quote.id)
                onNeedsRefresh()
                // Home has always refreshed the count after a copy and this
                // screen never did, so duplicating from here left the allowance
                // reading one too many for the rest of the session.
                await session.refreshQuoteUsage()
                toast = Toast(style: .success, message: "Copy saved as a draft")
            } catch let error where error.isQuoteAllowanceExhausted {
                await store.refreshEntitlement(forceReport: true)
                guard SubscriptionFlow.quotaRefusalOutcome(isPro: store.isPro) == .retryAfterEntitlementSync else {
                    await session.refreshQuoteUsage()
                    store.isPaywallPresented = true
                    return
                }
                do {
                    try await QuoteService.duplicateQuote(id: quote.id)
                    onNeedsRefresh()
                    await session.refreshQuoteUsage()
                    toast = Toast(style: .success, message: "Copy saved as a draft")
                } catch let retryError where retryError.isQuoteAllowanceExhausted {
                    await session.refreshQuoteUsage()
                    toast = Toast(style: .error, message: "Your subscription is still syncing. Try again in a moment.")
                } catch {
                    toast = Toast(style: .error, message: "Couldn't duplicate this quote")
                }
            } catch {
                toast = Toast(style: .error, message: "Couldn't duplicate this quote")
            }
        }
    }

    @MainActor
    private func previewPDF() {
        do {
            pdfPreviewURL = try QuotePDF.write(pdfDocument)
            showPDFPreview = true
        } catch {
            toast = Toast(style: .error, message: "Couldn't open the PDF")
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
        session.updateQuote(id: quote.id) { $0.pinned = newValue }
        Task {
            do {
                try await QuoteService.setPinned(id: quote.id, pinned: newValue)
            } catch {
                pinned = !newValue
                session.updateQuote(id: quote.id) { $0.pinned = !newValue }
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
        session.updateQuote(id: quote.id) { $0.title = trimmed }
        Task {
            do {
                try await QuoteService.setTitle(quoteId: quote.id, title: trimmed)
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) { title = previous }
                session.updateQuote(id: quote.id) { $0.title = previous }
                toast = Toast(style: .error, message: "Couldn't rename this quote")
            }
        }
    }

    /// The terms and the note that print at the foot of the quote.
    ///
    /// Both are set once in Quote defaults and go out on every quote, which is
    /// exactly why they belong on this screen: they are part of what the client
    /// receives, and the only place they could be read before was the PDF —
    /// after the decision to send it. Same order and same names the document
    /// gives them, so nothing here is a second version of anything there.
    @ViewBuilder private var documentFooter: some View {
        let terms = (session.businessProfile?.defaultTerms ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (session.businessProfile?.defaultNotes ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 20) {
            if !terms.isEmpty { footerBlock("Terms", terms) }
            if !notes.isEmpty { footerBlock("Notes", notes) }
        }
    }

    /// Headed the way the scope list above is headed — the label stepped back
    /// from the words it names, because what the quote says should be the
    /// darkest thing on the page.
    private func footerBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(displayTitle)
                    .font(.robotoSlab(29, relativeTo: .title))
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)

                chips

                jobDetailsSection
                    .padding(.top, 4)

                lineItemsSection
                    .padding(.top, 4)

                documentFooter
                    .padding(.top, 4)
            }
            // 20, matching Home and the rate card. A quote opened from the list
            // used to step 4pt inward from the row that was tapped.
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        // A document white in light mode, and a softer charcoal in dark mode:
        // distinct from both a black canvas and the cards laid on top of it.
        .background(Color(.quoteDetailBackground))
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
        .task(id: clientName) {
            let name = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                clientAddress = nil
                return
            }
            clientAddress = try? await QuoteService.customerAddress(named: name)
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
            // This one moves the quote between people: the Clients tab groups by
            // the name on it, so naming a different client has to reach the
            // shared list or the quote stays hanging under the old one.
            session.updateQuote(id: quote.id) { $0.clientName = current }
            Task { try? await QuoteService.setClient(quoteId: quote.id, name: current) }
        }
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(text: transcriptText, unreachable: transcriptUnreachable)
        }
        .sheet(isPresented: $showPDFPreview) {
            if let pdfPreviewURL {
                QuickLookPreview(url: pdfPreviewURL)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showEdit) {
            EditQuoteView(quoteId: quote.id,
                          title: title,
                          jobSummary: jobSummary,
                          scope: scope) { newSummary, newScope in
                jobSummary = newSummary
                scope = newScope
                session.updateQuote(id: quote.id) {
                    $0.jobSummary = newSummary
                    $0.scope = newScope
                }
            }
        }
        .sheet(isPresented: $showLineItems) {
            LineItemsSheet(quoteId: quote.id,
                           currency: currency,
                           taxRate: quote.taxRate,
                           lineItems: lineItems) { _, newTotal in
                total = newTotal
                session.updateQuote(id: quote.id) { $0.total = newTotal }
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
            ShareQuotePanel(quoteId: quote.id,
                            title: displayTitle,
                            subtitle: shareSubtitle,
                            shareText: shareText,
                            document: pdfDocument) {
                // Sharing a draft marks it as Sent (don't downgrade later statuses).
                if status == "draft" { changeStatus(to: "sent") }
            }
        }
        .sheet(item: $pendingCurrency) { target in
            currencyConversionSheet(for: target)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > 44
        } action: { _, scrolledPastTitle in
            withAnimation(.easeInOut(duration: 0.2)) {
                showHeaderTitle = scrolledPastTitle
            }
        }
        // Answers the tap. A selection tick for any change, and the fuller
        // success pattern for Accepted — the one status that means the job was
        // won, which Home already marks the same way.
        //
        // Keyed to the optimistic change rather than to the write landing: the
        // tap should feel instant, the same reasoning the pin uses. A failed
        // write reverts `status` and ticks again, which is honest — the state
        // did change back.
        .sensoryFeedback(trigger: status) { _, new in
            new == "accepted" ? .success : .selection
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
                .tint(Self.recordBlue)
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
                        previewPDF()
                    } label: {
                        Label {
                            Text("View PDF")
                        } icon: {
                            Image(.quoteDocument)
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                        }
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
                        Label {
                            Text("Delete quote")
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
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
                    do {
                        try await QuoteService.deleteQuote(id: quote.id)
                    } catch {
                        toast = Toast(style: .error, message: "Couldn't delete this quote")
                        return
                    }

                    QuoteExpiryNotifications.cancel(quote)
                    // Drop it from the shared list too, so the Clients tab — which
                    // is drawn from it — loses the quote and the client if it was
                    // their last. `onDeleted` only tells the screen we came from.
                    session.removeQuote(id: quote.id)
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
