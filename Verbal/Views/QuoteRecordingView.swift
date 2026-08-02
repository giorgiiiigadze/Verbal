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

    var body: some View {
        NavigationStack {
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
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .animation(.easeInOut(duration: 0.35), value: isGenerating)
            }
            .background(Color(.homeBackground))
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

    /// Run the AI extraction, then cross-fade the transcript into the review document.
    private func generate() {
        guard hasText, generated == nil, !isGenerating else { return }
        isGenerating = true
        notEnough = false
        notEnoughNote = ""
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
                Text("Generating your quote…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("Surface"), in: Capsule())

            Text("We'll turn your description into an itemized quote in a moment.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()
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
                        // Resuming to add more: drop the generated review so the
                        // transcript reappears and re-generates on the next stop.
                        // The banked draft goes too — the next stop replaces it.
                        if generated != nil || notEnough {
                            generated = nil
                            notEnough = false
                            discardDraft()
                        }
                        // Resume from whatever is currently shown (incl. hand-edits).
                        recorder.seed(transcriptText)
                        await recorder.start()
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
