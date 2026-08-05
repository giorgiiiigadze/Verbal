//
//  QuoteRecordingView.swift
//  Verbal
//

import SwiftUI

struct QuoteRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var recorder = QuoteRecorder()
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
    /// Currency for the quote being built — always the user's Settings default.
    /// Changing a quote's currency happens later, on the detail page.
    @State private var currency = AppCurrency.current.rawValue

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
                            if recorder.isRecording {
                                Text(displayTitle)
                                    .foregroundStyle(.secondary)
                                    .shimmer(active: recorder.hasContent)
                            } else {
                                TextField("Untitled quote", text: $title, axis: .vertical)
                                    .foregroundStyle(Color(.mainText))
                                    .textFieldStyle(.plain)
                                    .lineLimit(2)
                            }
                        }
                        .font(.robotoSlab(34, relativeTo: .largeTitle))

                        if generated != nil || notEnough {
                            chips
                                .transition(.opacity)
                        }

                        if isGenerating {
                            statusBanner
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        contentArea
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Something at the very end to scroll to while dictating.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.transcriptEndAnchor)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .animation(.easeInOut(duration: 0.35), value: isGenerating)
                }
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
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
                .toast($toast)
                // Record button: firm press-down feel on start, gentle release on stop.
                .sensoryFeedback(trigger: recorder.isRecording) { _, isRecording in
                    isRecording ? .impact(weight: .medium) : .impact(weight: .light)
                }
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
                .onChange(of: recorder.isRecording) { wasRecording, isRecording in
                    // When a recording finishes with content, generate the quote.
                    if wasRecording && !isRecording {
                        generate()
                    }
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
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) {
                            // Closing keeps the draft; it just carries any late edits
                            // to the title or client with it.
                            if let pending = bankTask {
                                Task {
                                    if let id = await pending.value { await applyEdits(to: id) }
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
                                Label("Discard recording", systemImage: "trash")
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
            guard let result = try? await QuoteService.generate(transcript: transcriptText) else {
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
            try? await QuoteService.save(
                result, transcript: bankedTranscript, title: bankedTitle,
                currency: bankedCurrency, clientName: bankedClient
            )
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
            }
        }
    }

    /// Start (or resume) recording from whatever is currently on screen.
    private func beginRecording() async {
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
        await recorder.start()
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
                dismiss()
                return
            }
            // The bank didn't land, usually because the phone was offline. This
            // is the retry, and it keeps the old confirm-then-leave behaviour.
            do {
                _ = try await QuoteService.save(generated, transcript: transcriptText, title: title,
                                                currency: currency, clientName: clientName)
                toast = Toast(style: .success, message: "Quote saved")
                try? await Task.sleep(for: .seconds(1.0))
                dismiss()
            } catch {
                toast = Toast(style: .error, message: "Couldn't save quote")
            }
        }
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
                        Text(notEnoughNote)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(.blueAccentText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(.royalBlue25),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    transcript
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
                if notEnough {
                    QuoteChip(text: "Needs detail") {
                        Image(systemName: "exclamationmark.circle")
                    }
                } else {
                    QuoteChip(text: "Draft") {
                        Image(systemName: "pencil")
                    }
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
        VStack(alignment: .leading, spacing: 16) {
            Text(quote.jobSummary)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(Color(.mainText))
                .frame(maxWidth: .infinity, alignment: .leading)

            ScopeList(items: quote.scope)
                .padding(.top, 8)

            if !quote.lineItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Line items")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(.mainText))
                    VStack(spacing: 0) {
                        ForEach(quote.lineItems) { item in
                            LineItemRow(
                                description: item.description,
                                quantityText: item.quantityText,
                                isMissingPrice: item.isMissingPrice,
                                lineTotal: item.lineTotal,
                                currencyCode: currency
                            )
                            if item.id != quote.lineItems.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                }
                .padding(.top, 8)

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

    private var transcript: some View {
        Group {
            if recorder.isRecording {
                // Live transcription (read-only while recording).
                Text(transcriptText.isEmpty ? "Listening…" : transcriptText)
                    .foregroundStyle(transcriptText.isEmpty ? .secondary : Color(.mainText))
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

            Text(recorder.elapsedText)
                .font(.body.monospacedDigit())
                .foregroundStyle(Color(.mainText))

            Spacer()

            Button {
                if generated == nil {
                    generate()
                } else {
                    save()
                }
            } label: {
                Group {
                    if isSaving || isGenerating {
                        ProgressView().tint(.white)
                    } else {
                        // "Done" once a quote exists — it is banked, or about to
                        // be, so there is nothing left to save. The label doesn't
                        // wait on the write; flickering Save→Done would only
                        // advertise a round trip the user shouldn't have to think
                        // about.
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
            .disabled(!hasText || recorder.isRecording || isSaving || isGenerating)
        }
    }
}
