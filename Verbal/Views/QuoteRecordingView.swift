//
//  QuoteRecordingView.swift
//  Verbal
//

import SwiftUI

struct QuoteRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = QuoteRecorder()

    var body: some View {
        NavigationStack {
            ScrollView {
                transcript
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            .background(Color.white)
            .navigationTitle("Untitled quote")
            .navigationSubtitle("AI names this after you finish")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        Group {
            if recorder.hasContent {
                Text(recorder.transcript)
                    .font(.body)
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
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(.mainText))
                    .frame(width: 40, height: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(recorder.state == .preparing)

            Spacer()

            HStack(spacing: 8) {
                Text(recorder.elapsedText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Color(.mainText))
                AudioLevelDots(level: CGFloat(recorder.audioLevel))
            }

            Spacer()

            Button {
                Task { await recorder.stop() }
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .frame(height: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }
}

/// Row of blue dots that react to the live microphone level (a voice meter).
private struct AudioLevelDots: View {
    /// Normalized mic level, 0...1.
    var level: CGFloat

    // Center dots respond most strongly, like a simple equalizer.
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                let intensity = min(1, level * weights[index] * 1.8)
                Circle()
                    .fill(Color(.royalBlue500))
                    .frame(width: 5, height: 5)
                    .scaleEffect(0.6 + intensity)
                    .opacity(0.3 + intensity * 0.7)
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
    }
}
