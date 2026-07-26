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

    private var displayTitle: String {
        title.isEmpty ? "Untitled quote" : title
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Group {
                        if recorder.isRecording {
                            // Non-editable while the AI is "generating" — shows the shimmer.
                            Text(title.isEmpty ? "Untitled quote" : title)
                                .foregroundStyle(Color(white: 0.72))
                                .shimmer(active: true)
                        } else {
                            TextField("Untitled quote", text: $title)
                                .foregroundStyle(Color(.mainText))
                                .textFieldStyle(.plain)
                        }
                    }
                    .font(.largeTitle)

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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if showHeaderTitle {
                        Text(displayTitle)
                            .font(.headline)
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

    // MARK: - Transcript

    private var transcript: some View {
        Group {
            if recorder.hasContent {
                Text(recorder.transcript)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(.mainText))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Tap the mic and describe the job in your own words.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
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
                Task { await recorder.stop() }
                // TODO: run AI extraction + persist the quote
                dismiss()
            } label: {
                Text("Save")
                    .font(.body.weight(.semibold))
                    .frame(height: 24)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(.royalBlue600))
            .controlSize(.large)
            .disabled(!recorder.hasContent || recorder.isRecording)
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
