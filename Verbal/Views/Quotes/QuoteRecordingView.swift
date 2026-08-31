//
//  QuoteRecordingView.swift
//  Verbal
//

import SwiftUI
import UIKit

struct QuoteRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = QuoteRecorder()
    /// A short history of microphone levels, newest last, so the meter reads as
    /// a trace of what was just said rather than one bar twitching.
    @State private var levels: [Float] = []
    @State private var title = ""
    @State private var showHeaderTitle = false
    @State private var isSaving = false
    @State private var isGenerating = false
    @State private var generated: GeneratedQuote?
    /// True when generation ran but the transcript wasn't enough to build a quote.
    @State private var notEnough = false
    /// The AI's "there wasn't enough here" note. Held apart from the transcript
    /// so reading it never costs the user the words they actually spoke.
    @State private var notEnoughNote = ""
    /// When the current generation finished — drives the date chip.
    @State private var generatedAt = Date()
    @State private var showTranscript = false
    /// Who the quote is for — the one detail the transcript can't provide.
    @State private var clientName = ""
    @State private var showClientSheet = false
    /// Drives the microphone priming sheet, and whether it reads as an
    /// explanation ahead of the system dialog or as a route to Settings.
    @State private var showMicPermission = false
    @State private var micAccessBlocked = false
    /// Offers the prices the extraction was missing to the rate card.
    @State private var showSaveRates = false
    /// Which of the generating phrases the banner is currently showing.
    @State private var phraseIndex = 0
    /// Set when the user accepts from that sheet, so recording starts once the
    /// sheet has closed rather than under it.
    @State private var startAfterMicPermission = false
    @State private var toast: Toast?
    /// Named only when the user has overridden the automatic choice: the
    /// language the mic is listening in. Silence is the right default, but
    /// someone who set this deliberately — or by accident — should be able to
    /// see it where the words are coming out wrong.
    @State private var dictationOverride: String?
    /// Currency for the quote being built — always the user's Settings default.
    /// Changing a quote's currency happens later, on the detail page.
    @State private var currency = AppCurrency.current.rawValue
    @AppStorage(RecordingPreferences.hapticsEnabledKey) private var recordingHapticsEnabled = true

    /// Editable transcript — mirrors live transcription, editable by hand when stopped.
    @State private var transcriptText = ""

    /// The in-flight (or finished) write of the draft row, yielding its id. Held
    /// as a task rather than a plain id because the write runs in the background
    /// while the user reads the quote: anything that needs the id — finishing,
    /// closing, discarding — awaits this instead of racing it.
    @State private var bankTask: Task<UUID?, Never>?
    /// What was actually persisted, so finishing only writes back real changes.
    @State private var savedTitle = ""
    @State private var savedClient = ""

    private let scheduledVisit: ScheduledVisit?
    private let onSavedQuote: ((UUID) -> Void)?
    /// Called instead of `onSavedQuote` when the server refused the save
    /// because today's free quotes are gone.
    ///
    /// Handed back to the owner rather than acted on here, because the paywall
    /// is a sheet on `MainTabView` and this is a sheet on `MainTabView`:
    /// raising one from inside the other, mid-dismissal, is how a sheet gets
    /// silently swallowed — the lesson recorded at the top of that file. The
    /// owner raises it once this one has actually gone.
    private let onAllowanceExhausted: (() -> Void)?

    private enum Field: Hashable { case title, transcript }
    /// Which field the keyboard belongs to, if any. Both fields are vertical,
    /// so Return makes a new line and can't put the keyboard away — the bottom
    /// bar does that instead, see `bottomBar`.
    @FocusState private var focus: Field?

    init(scheduledVisit: ScheduledVisit? = nil,
         onSavedQuote: ((UUID) -> Void)? = nil,
         onAllowanceExhausted: (() -> Void)? = nil) {
        self.onAllowanceExhausted = onAllowanceExhausted
        self.scheduledVisit = scheduledVisit
        self.onSavedQuote = onSavedQuote
        _title = State(initialValue: "")
        _clientName = State(initialValue: scheduledVisit?.title ?? "")
    }

    private var hasText: Bool {
        !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayTitle: String {
        title.isEmpty ? "Untitled quote" : title
    }

    /// Identifies the zero-height view pinned below the transcript.
    private static let transcriptEndAnchor = "transcriptEnd"

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Group {
                            // Paused counts as mid-session: a call arriving
                            // shouldn't turn the title into an editable field
                            // under the user's thumb.
                            if recorder.isSessionActive {
                                Text(displayTitle)
                                    .foregroundStyle(.secondary)
                                    .shimmer(active: recorder.hasContent)
                            } else {
                                TextField("Untitled quote", text: $title, axis: .vertical)
                                    .focused($focus, equals: .title)
                                    .foregroundStyle(Color(.mainText))
                                    .textFieldStyle(.plain)
                                    .lineLimit(2)
                            }
                        }
                        .font(.robotoSlab(29, relativeTo: .title))

                        // Only over a quote that exists. When the transcript
                        // wasn't enough there is nothing to name a client on and
                        // nothing dated "just now", and the panel below already
                        // says what went wrong in full — so a row of chips
                        // repeating it in three fragments offers work on a
                        // document that was never made.
                        if generated != nil {
                            chips
                                .transition(.opacity)
                        }

                        if isGenerating {
                            statusBanner
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if recorder.isPaused {
                            pausedNotice
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        contentArea
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Something at the very end to scroll to while dictating.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.transcriptEndAnchor)
                    }
                    // 20, as everywhere else. The review that appears here shares
                    // its shape with the quote screen, and the two were 4pt apart.
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .animation(.easeInOut(duration: 0.35), value: isGenerating)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color(.homeBackground))
                // Follow the words down as they arrive. Speech runs past the
                // bottom of the screen after a few lines, and a job description is
                // the point at which the user most wants to see that it heard
                // "eight metres" and not "eighty".
                //
                // Only while recording: once stopped the transcript is theirs to
                // scroll and edit, and yanking it around would fight them.
                .onChange(of: transcriptText) { _, _ in
                    guard recorder.isRecording else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        scroll.scrollTo(Self.transcriptEndAnchor, anchor: .bottom)
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
                .safeAreaInset(edge: .bottom) {
                    bottomBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                .toast($toast)
                // The magic moment — the spoken job became a quote.
                .sensoryFeedback(.success, trigger: generated != nil) { wasGenerated, isGenerated in
                    !wasGenerated && isGenerated
                }
                .sheet(isPresented: $showClientSheet) {
                    ClientSheet(name: $clientName)
                }
                .sheet(isPresented: $showTranscript) {
                    TranscriptSheet(text: transcriptText, editable: $transcriptText) {
                        // Regenerate: clear the current result and re-run the AI extraction.
                        // The banked draft goes with it, so the rerun replaces the
                        // quote rather than leaving two.
                        generated = nil
                        notEnough = false
                        discardDraft()
                        generate()
                    }
                }
                .onChange(of: recorder.transcript) { _, newValue in
                    if recorder.isRecording { transcriptText = newValue }
                }
                // Stopping used to generate on its own. The button says pause,
                // and pausing meant the quote was extracted then and there — so
                // catching a breath, checking a measurement or correcting a word
                // all cost a generation nobody asked for, and the only way to add
                // a second thought was to let it finish and record again.
                //
                // Pausing now only pauses. Generate is a button, and it has been
                // sitting there the whole time.
                // Leaving the app gives the microphone away: iOS suspends the
                // process and the engine stops. Nothing here was noticing, so
                // the timer ran on and the screen went on claiming to listen.
                // `.background`, not `.inactive` — the latter fires for a glance
                // at the app switcher or a pull-down of notifications.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .background, recorder.isRecording else { return }
                    Task { await recorder.interrupt() }
                }
                // The recorder has published a level all along and nothing ever
                // read it. Sampled straight from the audio tap, so it moves with
                // the voice rather than with the transcription behind it.
                .onChange(of: recorder.audioLevel) { _, level in
                    guard recorder.isRecording else { return }
                    levels.append(level)
                    if levels.count > LevelTrace.barCount {
                        levels.removeFirst(levels.count - LevelTrace.barCount)
                    }
                }
                .onChange(of: recorder.isRecording) { _, isRecording in
                    // Cleared on both edges: a trace left over from the last
                    // burst would draw someone else's voice on the next one.
                    if !isRecording { levels.removeAll() }
                }
                .onChange(of: recorder.errorMessage) { _, message in
                    // Surface mic / speech-permission or engine failures — otherwise
                    // tapping the mic would appear to do nothing.
                    if let message { toast = Toast(style: .error, message: message) }
                }
                .onAppear {
                    // Use the current Settings currency each time the sheet opens.
                    currency = AppCurrency.current.rawValue
                }
                // Read each time the sheet opens, so a language changed in
                // Settings is named the next time the mic is picked up.
                .task {
                    guard DictationLanguage.isOverridden,
                          let locale = await DictationLanguage.resolved() else {
                        dictationOverride = nil
                        return
                    }
                    dictationOverride = DictationLanguage.label(for: locale)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) {
                            // Closing keeps the draft; it just carries any late edits
                            // to the title or client with it.
                            if let pending = bankTask {
                                Task {
                                    if let id = await pending.value {
                                        await applyEdits(to: id)
                                        await MainActor.run { onSavedQuote?(id) }
                                    }
                                }
                            }
                            dismiss()
                        }
                    }
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
                            transcriptText = removingLastWord(from: transcriptText)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        // Once the quote is generated the transcript is history — trimming
                        // words from it no longer changes anything on screen. After a
                        // "not enough detail" pass it is still the live transcript, so
                        // undo keeps working there.
                        .disabled(transcriptText.isEmpty || recorder.isRecording
                                  || isGenerating || generated != nil)
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if generated != nil || notEnough {
                                Button {
                                    showTranscript = true
                                } label: {
                                    Label("View transcript", systemImage: "text.quote")
                                }
                            }
                            Button(role: .destructive) {
                                Task { await recorder.stop() }
                                recorder.reset()
                                discardDraft()
                                dismiss()
                            } label: {
                                Label {
                                    Text("Discard recording")
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
            }
        }
        // Attached to the NavigationStack rather than stacked alongside the
        // client and transcript sheets inside it: a third .sheet on that same
        // view is silently ignored, so this one simply never appeared.
        .sheet(isPresented: $showMicPermission, onDismiss: {
            guard startAfterMicPermission else { return }
            startAfterMicPermission = false
            Task { await beginRecording() }
        }) {
            MicPermissionSheet(isBlocked: micAccessBlocked) {
                startAfterMicPermission = true
            }
        }
        .sheet(isPresented: $showSaveRates) {
            SaveRatesSheet(items: unpricedItems, currency: currency) { prices, saved in
                Task {
                    await applyPrices(prices)
                    await session.refreshRateCard()
                    if saved > 0 {
                        toast = Toast(style: .success,
                                      message: "\(saved) rate\(saved == 1 ? "" : "s") saved")
                    }
                }
            }
        }
    }

    /// Put the prices just typed onto the quote as well as the rate card. Doing
    /// only the latter would leave the user staring at the same "Needs price"
    /// line they had just given a number for, and typing it again in the editor.
    private func applyPrices(_ prices: [UUID: Double]) async {
        guard var result = generated, !prices.isEmpty else { return }

        var touched: [Int] = []
        for index in result.lineItems.indices {
            guard let price = prices[result.lineItems[index].id] else { continue }
            result.lineItems[index].unitPrice = price
            result.lineItems[index].priceSource = "rate_card"
            // An unpriced line often carries no quantity either, and a unit
            // price without one still totals nothing.
            if result.lineItems[index].quantity == nil {
                result.lineItems[index].quantity = 1
            }
            touched.append(index)
        }
        withAnimation { generated = result }

        // The draft was banked the moment it generated, so the stored copy has
        // to learn the same prices or the saved quote won't match the screen.
        guard let quoteID = await bankTask?.value else { return }
        for index in touched {
            let item = result.lineItems[index]
            guard let quantity = item.quantity, let unitPrice = item.unitPrice else { continue }
            try? await QuoteService.setLineItemPrice(
                quoteId: quoteID, position: index, quantity: quantity, unitPrice: unitPrice)
        }
        let subtotal = result.lineItems.reduce(0.0) { $0 + ($1.lineTotal ?? 0) }
        try? await QuoteService.updateSubtotal(id: quoteID, subtotal: subtotal)
    }

    /// The generated lines the extraction had no price for, as rate candidates.
    private var unpricedItems: [UnpricedItem] {
        (generated?.lineItems ?? []).filter(\.isMissingPrice).map {
            UnpricedItem(id: $0.id, name: $0.description, unit: $0.unit, type: $0.type)
        }
    }

    /// Run the AI extraction, then cross-fade the transcript into the review document.
    private func generate() {
        guard hasText, generated == nil, !isGenerating else { return }
        isGenerating = true
        notEnough = false
        notEnoughNote = ""
        // Always open on the first step, however the last run ended.
        phraseIndex = 0
        Task {
            defer { isGenerating = false }
            guard let result = try? await QuoteService.generate(transcript: transcriptText,
                                                             tradeContext: session.businessProfile?.trade) else {
                toast = Toast(style: .error, message: "Couldn't generate quote")
                return
            }
            generatedAt = Date()
            withAnimation(.easeInOut(duration: 0.5)) {
                if result.lineItems.isEmpty {
                    // Nothing quotable — show the AI's friendly note above the
                    // transcript. It must NOT replace the transcript: a recording
                    // is unrepeatable, and overwriting it would throw away the
                    // one thing the user can't get back.
                    notEnoughNote = result.jobSummary
                    notEnough = true
                } else {
                    generated = result
                    // Auto-fill the title from the AI's compact job title if the user
                    // hasn't typed their own.
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = result.title
                    }
                    // Same for the client: if the job was described as being for
                    // someone by name, that name was already extracted, and
                    // making the user type it again is asking them for something
                    // they just said. Anything they typed themselves wins.
                    if clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let suggested = result.clientName, !suggested.isEmpty {
                        clientName = suggested
                    }
                }
            }
            // Bank it straight away, before the user has a chance to lose it —
            // but in the background. The quote is on screen and they should be
            // reading it, not watching a spinner wait on four round trips.
            if !result.lineItems.isEmpty {
                startBanking(result)
            }
        }
    }

    /// Begin writing the generated quote to the server as a draft, so it survives
    /// the sheet being closed. Failure is deliberately silent — the task yields
    /// nil, finishing falls back to a normal save, and an offline phone never
    /// raises an error the user can do nothing about.
    private func startBanking(_ result: GeneratedQuote) {
        guard bankTask == nil else { return }
        let bankedTitle = title
        let bankedClient = clientName
        let bankedTranscript = transcriptText
        let bankedCurrency = currency
        savedTitle = bankedTitle
        savedClient = bankedClient
        bankTask = Task {
            let id = try? await QuoteService.save(
                result, transcript: bankedTranscript, title: bankedTitle,
                currency: bankedCurrency, clientName: bankedClient
            )
            // Counted here, where the row is known to exist. Home used to
            // refresh this when the sheet closed, but closing doesn't wait for
            // the insert — so the count was read before the ledger had the
            // quote in it, and stayed one short for the rest of the session.
            if id != nil {
                await session.refreshQuoteUsage()
            }
            return id
        }
    }

    /// Push edits made after the draft was banked. Only what changed is written.
    private func applyEdits(to id: UUID) async {
        if title != savedTitle {
            try? await QuoteService.updateTitle(id: id, title: displayTitle)
        }
        let trimmedClient = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        if clientName != savedClient, !trimmedClient.isEmpty {
            try? await QuoteService.setClient(quoteId: id, name: trimmedClient)
        }
    }

    /// Drop the banked draft — the quote is being replaced by a fresh generation,
    /// or thrown away outright. Without this, every re-record would leave an
    /// orphan behind in the Drafts list. Awaits the write first: a draft still in
    /// flight would otherwise land after the delete and survive it.
    private func discardDraft() {
        guard let pending = bankTask else { return }
        bankTask = nil
        savedTitle = ""
        savedClient = ""
        Task {
            if let id = await pending.value {
                try? await QuoteService.deleteQuote(id: id)
                // And give the allowance back. The ledger never refunds a
                // delete on purpose, but this draft is being replaced by the
                // recording about to start — one quote is being made here, not
                // two, and charging for both would spend a free user's whole
                // day on a single re-record.
                try? await QuoteService.voidQuoteUsage(quoteID: id)
                await session.refreshQuoteUsage()
            }
        }
    }

    /// Says the microphone was taken away, and stays until it's picked back up.
    /// A toast would be gone in three seconds, and not noticing is the whole
    /// failure this exists to fix.
    ///
    /// It carried Resume and Finish buttons at first, which was a panel offering
    /// what the bottom bar already offers a few points below — the mic resumes,
    /// Generate finishes. So it points at the mic instead of competing with it,
    /// and says nothing about the words being kept: they're on screen underneath,
    /// which makes the claim better than any sentence could.
    private var pausedNotice: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LineItemRow.amber)
                .frame(width: 7, height: 7)
            Text("Paused — tap the mic to continue.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    /// Start (or resume) recording from whatever is currently on screen.
    private func beginRecording() async {
        // The keyboard on its way down before the trace needs the room.
        focus = nil
        // Resuming to add more: drop the generated review so the transcript
        // reappears and re-generates on the next stop. The banked draft goes
        // too — the next stop replaces it.
        if generated != nil || notEnough {
            generated = nil
            notEnough = false
            notEnoughNote = ""
            discardDraft()
        }
        // Resume from whatever is currently shown (incl. hand-edits).
        recorder.seed(transcriptText)
        let recordingFeedback = recordingHapticsEnabled ? UIImpactFeedbackGenerator(style: .medium) : nil
        recordingFeedback?.prepare()
        await recorder.start()
        if recorder.isRecording {
            recordingFeedback?.impactOccurred()
        }
    }

    /// Removes the trailing word (plus its separating whitespace) — powers word-by-word undo.
    private func removingLastWord(from text: String) -> String {
        var result = text
        func isSeparator(_ c: Character) -> Bool { c == " " || c == "\n" }
        while let last = result.last, isSeparator(last) { result.removeLast() }
        while let last = result.last, !isSeparator(last) { result.removeLast() }
        while let last = result.last, isSeparator(last) { result.removeLast() }
        return result
    }

    private func save() {
        guard let generated else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            // Wait for the background write before deciding anything: a quick tap
            // on Done while it is still in flight would otherwise save a second copy.
            if let id = await bankTask?.value {
                await applyEdits(to: id)
                onSavedQuote?(id)
                dismiss()
                return
            }
            // The bank didn't land, usually because the phone was offline. This
            // is the retry, and it keeps the old confirm-then-leave behaviour.
            do {
                let id = try await QuoteService.save(generated, transcript: transcriptText, title: title,
                                                     currency: currency, clientName: clientName)
                onSavedQuote?(id)
                toast = Toast(style: .success, message: "Quote saved")
                try? await Task.sleep(for: .seconds(1.0))
                dismiss()
            } catch let error where error.isQuoteAllowanceExhausted {
                // A rejection can be an ordinary free-tier limit, but it can
                // also be the narrow gap after a renewal, restore or sign-in:
                // StoreKit already knows the account is Pro while Supabase has
                // not yet received its signed transaction. Reconcile and retry
                // once before offering a subscription to somebody who has one.
                await store.refreshEntitlement(forceReport: true)
                if SubscriptionFlow.quotaRefusalOutcome(isPro: store.isPro) == .retryAfterEntitlementSync {
                    await retrySaveAfterEntitlementSync(generated)
                } else {
                    await showPaywallForExhaustedAllowance()
                }
            } catch {
                toast = Toast(style: .error, message: "Couldn't save quote")
            }
        }
    }

    /// The first write was refused before the server had the user's current
    /// StoreKit entitlement. `refreshEntitlement()` above reports that signed
    /// transaction, so this is a fresh, single retry of the transactional RPC.
    /// A quota refusal here means the server still cannot see it; keeping the
    /// quote open with a sync message is truthful, while a paywall is not.
    private func retrySaveAfterEntitlementSync(_ quote: GeneratedQuote) async {
        do {
            let id = try await QuoteService.save(quote, transcript: transcriptText, title: title,
                                                 currency: currency, clientName: clientName)
            onSavedQuote?(id)
            toast = Toast(style: .success, message: "Quote saved")
            try? await Task.sleep(for: .seconds(1.0))
            dismiss()
        } catch let error where error.isQuoteAllowanceExhausted {
            await session.refreshQuoteUsage()
            toast = Toast(style: .error, message: "Your subscription is still syncing. Try again in a moment.")
        } catch {
            toast = Toast(style: .error, message: "Couldn't save quote")
        }
    }

    private func showPaywallForExhaustedAllowance() async {
        // The gate is the server's now, so this is reachable even though the
        // tab bar checked before the recording started — a quote banked on
        // another device, or a count that was already stale by the time this
        // one finished. Saying "couldn't save quote" about it would be
        // describing a paywall as a fault.
        await session.refreshQuoteUsage()
        onAllowanceExhausted?()
        dismiss()
    }

    // MARK: - Content (transcript ⇄ summary)

    @ViewBuilder
    private var contentArea: some View {
        ZStack(alignment: .topLeading) {
            if let generated {
                // The AI quote takes over from the transcript.
                reviewDocument(generated)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if notEnough, !notEnoughNote.isEmpty {
                        // The same string as the summary above, under
                        // another name, so it is set the same way.
                        Text(emphasizedSummary(notEnoughNote))
                            .foregroundStyle(Color(.blueAccentText))
                            // Wraps rather than truncating. This is the app
                            // explaining why it couldn't build a quote, and it
                            // was cutting itself off mid-sentence — the one
                            // message on this screen that has to be read whole.
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(.royalBlue25),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    transcript
                    if let dictationOverride {
                        Text("Listening in \(dictationOverride)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: generated != nil)
    }

    // MARK: - Quote chips (creator / date / status)

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                // Naming the client is the one detail the transcript can't
                // supply, so it leads the row and stays inviting until filled.
                Button { showClientSheet = true } label: {
                    QuoteChip(text: clientName.isEmpty ? "Add client" : clientName,
                              tinted: clientName.isEmpty) {
                        Image(systemName: clientName.isEmpty ? "person.badge.plus" : "person.fill")
                    }
                }
                .buttonStyle(.plain)

                QuoteChip(text: quoteDateLabel(generatedAt)) {
                    Image(systemName: "calendar")
                }
                QuoteChip(text: "Draft") {
                    Image(systemName: "pencil")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: - Status banner (while generating)

    /// What the banner says while the extraction runs. Each names a real step of
    /// the pipeline rather than filling time with a joke — the person watching
    /// is waiting on a number they are about to quote a customer, and cleverness
    /// at that moment reads as the app not taking the job seriously.
    private static let generatingPhrases = [
        "Reading the job",
        "Picking out the work",
        "Checking your rate card",
        "Pricing the items",
        "Adding it up",
        "Writing it up"
    ]

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // The brand mark stands in for a spinner — a light sweep runs
                // across it while the AI works.
                Image(.brandMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26)
                    .foregroundStyle(Color(.blueAccentText))
                    .shimmer(active: true, highlight: .white)

                // Each phrase pushes the last one up and out, so the banner
                // reads as movement through the work rather than one caption
                // sitting there for eight seconds.
                Text(Self.generatingPhrases[phraseIndex])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.blueAccentText))
                    .shimmer(active: true)
                    .id(phraseIndex)
                    .transition(.push(from: .top).combined(with: .opacity))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.surface), in: Capsule())
            // The outgoing phrase has to be trimmed at the capsule's edge, or
            // it slides out over the transcript behind it.
            .clipShape(Capsule())

            Text("We'll turn your description into an itemized quote in a moment.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()
        }
        // Tied to the banner's own lifetime: it starts when the banner appears
        // and is cancelled when generation ends and the banner goes away.
        .task { await cyclePhrases() }
    }

    private func cyclePhrases() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                phraseIndex = (phraseIndex + 1) % Self.generatingPhrases.count
            }
        }
    }

    @ViewBuilder
    private func reviewDocument(_ quote: GeneratedQuote) -> some View {
        // 20 and 4, exactly as the quote screen — the same document, so the
        // two were not allowed to drift apart by four points.
        VStack(alignment: .leading, spacing: 20) {
            Text(emphasizedSummary(quote.jobSummary))
                .foregroundStyle(Color(.mainText))
                .frame(maxWidth: .infinity, alignment: .leading)

            ScopeList(items: quote.scope)
                .padding(.top, 4)

            if !quote.lineItems.isEmpty {
                // The same card the quote screen uses. Its heading used to sit
                // outside as a large title while the saved quote's sat inside a
                // header bar — the same table, introduced two different ways.
                // No expand control: this quote isn't saved yet, so there's
                // nothing to edit through.
                LineItemsCard {
                    ForEach(quote.lineItems) { item in
                        LineItemRow(
                            description: item.description,
                            quantityText: item.quantityText,
                            isMissingPrice: item.isMissingPrice,
                            lineTotal: item.lineTotal,
                            currencyCode: currency,
                            confidence: item.confidence
                        )
                        if item.id != quote.lineItems.last?.id { Divider() }
                    }
                }
                .padding(.top, 4)

                let subtotal = quote.lineItems.compactMap(\.lineTotal).reduce(0, +)
                let missing = quote.lineItems.filter(\.isMissingPrice).count
                HStack {
                    Text("Total").font(.headline).foregroundStyle(Color(.mainText))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(subtotal, format: AppCurrency.format(code: currency))
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color(.mainText))
                        if missing > 0 {
                            Text("excl. \(missing) unpriced item\(missing == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // What the model wasn't sure about, in its own words. It has
                // been producing these all along — the schema has always
                // required them — and nothing ever read them, so the one part
                // of the extraction that knows where it might be wrong stayed
                // invisible. Sits above the rate-card prompt because the two
                // usually concern the same lines.
                if !quote.flags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Worth checking")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LineItemRow.amber)
                        ForEach(quote.flags, id: \.self) { flag in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(LineItemRow.amber)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                Text(flag)
                                    .font(.footnote)
                                    .foregroundStyle(Color(.mainText))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LineItemRow.amber.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.top, 4)
                }

                // The gaps are on screen and named; this is the cheapest moment
                // to teach the rate card, because the user is looking at exactly
                // the prices Verbal didn't know.
                if missing > 0 {
                    Button {
                        showSaveRates = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 17))
                                .foregroundStyle(Color(.blueAccentText))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save these to your rate card")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(.mainText))
                                Text("They'll be priced automatically next time.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.royalBlue25),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }

    /// The settled words in full ink, the recogniser's current guess behind
    /// them in grey.
    ///
    /// Both halves were being glued into one string in one colour, so a word the
    /// model is still unsure of looked exactly like one it had committed to.
    /// That matters more here than it would elsewhere: "eighty" that is still
    /// grey may yet become "eight", and a quantity is what this app is for.
    ///
    /// It also makes the wait legible. Nothing arrives sooner — the recogniser
    /// needs its few hundred milliseconds of audio either way — but words now
    /// appear the moment there is a guess and visibly firm up, rather than the
    /// screen sitting still until one is certain.
    /// Built as an attributed string rather than by adding two `Text`s — that
    /// operator is deprecated as of iOS 26. Only the colour is set on each run,
    /// so the font applied to the group still reaches both.
    private var liveTranscript: some View {
        var settled = AttributedString(recorder.finalizedText)
        settled.foregroundColor = Color(.mainText)

        var guessing = AttributedString(recorder.volatileText)
        guessing.foregroundColor = .secondary

        return Text(settled + guessing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var transcript: some View {
        Group {
            if recorder.isRecording {
                // Live transcription (read-only while recording).
                if recorder.transcript.isEmpty {
                    Text("Listening…")
                        .foregroundStyle(.secondary)
                } else {
                    liveTranscript
                }
            } else if isGenerating {
                // Frozen, shimmering while the AI summarizes.
                Text(transcriptText)
                    .foregroundStyle(Color(.mainText))
            } else {
                // Editable by hand when stopped; placeholder when empty.
                TextField(
                    "Tap the mic and describe the job in your own words.",
                    text: $transcriptText,
                    axis: .vertical
                )
                .focused($focus, equals: .transcript)
                .foregroundStyle(Color(.mainText))
            }
        }
        .font(.callout)
        .fontWeight(.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom bar (record / timer / cancel)

    private var bottomBar: some View {
        HStack {
            Button {
                Task {
                    if recorder.isRecording {
                        await recorder.stop()
                    } else {
                        // Make the case for the microphone before iOS asks. Its
                        // dialog appears once per install and explains nothing,
                        // and a refusal there can only be undone in Settings.
                        switch QuoteRecorder.access {
                        case .ready:
                            await beginRecording()
                        case .notAsked:
                            micAccessBlocked = false
                            showMicPermission = true
                        case .blocked:
                            micAccessBlocked = true
                            showMicPermission = true
                        }
                    }
                }
            } label: {
                Image(systemName: recorder.isRecording ? "pause.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(.mainText))
                    .frame(width: 56, height: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(recorder.state == .preparing)

            Spacer()

            // While recording, the trace is the point and the clock is a
            // caption under it. Nobody quoting a bathroom cares that it has
            // taken ninety seconds; they care that the phone can hear them, and
            // until now the only evidence of that was a number going up while
            // recognition lagged behind their voice.
            VStack(spacing: 3) {
                if recorder.isRecording {
                    LevelTrace(levels: levels)
                        .frame(height: 22)
                        .transition(.opacity)
                }
                Text(recorder.elapsedText)
                    .font(recorder.isRecording
                          ? .caption.monospacedDigit()
                          : .body.monospacedDigit())
                    .foregroundStyle(recorder.isRecording ? .secondary : Color(.mainText))
            }
            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)

            Spacer()

            // While the keyboard is up this corner is the only control under the
            // user's thumb, and Generate is the wrong one — they are mid-sentence,
            // and nothing here can put the keyboard away. So it becomes the glyph
            // that can, in plain glass rather than blue: while typing the bar is
            // two utilities, and the action worth a colour comes back with the
            // screen. Same glyph, same reasoning, as the profile page.
            Button {
                if focus != nil {
                    focus = nil
                } else {
                    if generated == nil {
                        generate()
                    } else {
                        save()
                    }
                }
            } label: {
                Group {
                    if focus != nil {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 20, weight: .semibold))
                    } else if isSaving || isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(generated == nil ? "Generate" : "Done")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(.royalBlue600))
            .controlSize(.large)
            .disabled(
                focus == nil &&
                (!hasText || recorder.isRecording || isSaving || isGenerating)
            )
        }
        .animation(.easeInOut(duration: 0.2), value: focus)
    }
}
