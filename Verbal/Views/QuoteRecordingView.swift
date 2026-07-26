//
//  QuoteRecordingView.swift
//  Verbal
//

import SwiftUI

struct QuoteRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = QuoteRecorder()
    @State private var title = ""
    @State private var showHeaderTitle = false
    @State private var isSaving = false
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
                            // Non-editable while recording; shimmers once the user starts speaking.
                            Text(title.isEmpty ? "Untitled quote" : title)
                                .foregroundStyle(Color(white: 0.72))
                                .shimmer(active: recorder.hasContent)
                        } else {
                            TextField("Untitled quote", text: $title)
                                .foregroundStyle(Color(.mainText))
                                .textFieldStyle(.plain)
                        }
                    }
                    .font(.robotoSlab(34, relativeTo: .largeTitle))

                    transcript
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
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
            .onChange(of: recorder.transcript) { _, newValue in
                if recorder.isRecording { transcriptText = newValue }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if showHeaderTitle {
                        Text(displayTitle)
                            .font(.robotoSlab(17, relativeTo: .headline))
                            .foregroundStyle(Color(.mainText))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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

    private func save() {
        isSaving = true
        Task {
            await recorder.stop()
            do {
                try await QuoteService.createQuote(transcript: transcriptText, title: title)
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

    // MARK: - Transcript

    private var transcript: some View {
        Group {
            if recorder.isRecording {
                // Live transcription (read-only while recording).
                Text(transcriptText.isEmpty ? "Listening…" : transcriptText)
                    .foregroundStyle(transcriptText.isEmpty ? .secondary : Color(.mainText))
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
                Task { await recorder.toggle() }
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
                save()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Save").font(.body.weight(.semibold))
                    }
                }
                .frame(height: 24)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(.mainText))
            .controlSize(.large)
            .disabled(!hasText || recorder.isRecording || isSaving)
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
