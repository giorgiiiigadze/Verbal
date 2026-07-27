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
    /// When the current generation finished — drives the date chip.
    @State private var generatedAt = Date()
    @State private var showTranscript = false
    @State private var toast: Toast?

    /// Editable transcript — mirrors live transcription, editable by hand when stopped.
    @State private var transcriptText = ""


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
                                .foregroundStyle(Color(white: 0.72))
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
            .background(Color(.mainBackground))
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
            .sheet(isPresented: $showTranscript) {
                TranscriptSheet(text: transcriptText, editable: $transcriptText) {
                    // Regenerate: clear the current result and re-run the AI extraction.
                    generated = nil
                    notEnough = false
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
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
                    .disabled(transcriptText.isEmpty || recorder.isRecording)
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
        Task {
            defer { isGenerating = false }
            guard let result = try? await QuoteService.generate(transcript: transcriptText) else {
                toast = Toast(style: .error, message: "Couldn't generate quote")
                return
            }
            generatedAt = Date()
            withAnimation(.easeInOut(duration: 0.5)) {
                if result.lineItems.isEmpty {
                    // Nothing quotable — drop the AI's friendly note straight into the
                    // transcript so the user can read it and keep editing in place.
                    transcriptText = result.jobSummary
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
            do {
                try await QuoteService.save(generated, transcript: transcriptText, title: title)
                isSaving = false
                toast = Toast(style: .success, message: "Quote saved")
                try? await Task.sleep(for: .seconds(1.0))
                dismiss()
            } catch {
                isSaving = false
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
                transcript
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: generated != nil)
    }

    // MARK: - Quote chips (creator / date / status)

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                QuoteChip(text: creatorName) {
                    AvatarView(image: session.avatarImage,
                               urlString: session.profile?.avatarUrl,
                               size: 22)
                }
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
        .scrollClipDisabled()
    }

    /// First name only, so the chip stays compact.
    private var creatorName: String {
        guard let full = session.profile?.fullName, !full.isEmpty else { return "You" }
        return String(full.split(separator: " ").first ?? "")
    }

    // MARK: - Status banner (while generating)

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
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

            if !quote.lineItems.isEmpty {
                VStack(spacing: 0) {
                    ForEach(quote.lineItems) { item in
                        LineItemRow(
                            description: item.description,
                            quantityText: item.quantityText,
                            isMissingPrice: item.isMissingPrice,
                            lineTotal: item.lineTotal
                        )
                        if item.id != quote.lineItems.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                let subtotal = quote.lineItems.compactMap(\.lineTotal).reduce(0, +)
                let missing = quote.lineItems.filter(\.isMissingPrice).count
                HStack {
                    Text("Total").font(.headline).foregroundStyle(Color(.mainText))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(subtotal, format: .number.precision(.fractionLength(2)))
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
                        Text(generated == nil ? "Generate" : "Save")
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

// MARK: - Shimmer (AI-style highlight sweep)

private struct ShimmerModifier: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(
                        colors: [.clear, Color(white: 0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.5)
                    .offset(x: -width * 0.5 + phase * (width + width * 0.5))
                }
                .mask(content)
                .allowsHitTesting(false)
                .opacity(active ? 1 : 0)
                .animation(.easeInOut(duration: 0.45), value: active)
            }
            .onChange(of: active) { _, isActive in
                if isActive {
                    phase = 0
                    withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { phase = 0 }
                }
            }
    }
}

private extension View {
    func shimmer(active: Bool) -> some View { modifier(ShimmerModifier(active: active)) }
}
