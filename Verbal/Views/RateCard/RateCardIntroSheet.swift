//
//  RateCardIntroSheet.swift
//  Verbal
//
//  A first-use explanation for the rate card. It uses the same focused shape
//  as the recording intro: one idea, three benefits, and one way forward.
//

import SwiftUI

struct RateCardIntroSheet: View {
    var onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Image("RateCardIntroTag")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .foregroundStyle(Color(.mainText))
                    .padding(.top, 70)

                Text("Your prices,\nready to quote.")
                    .font(.system(size: 38, design: .serif).weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(.mainText))
                    .padding(.top, 30)

                VStack(alignment: .center, spacing: 24) {
                    benefit("tag", "Save the prices you charge, once")
                    benefit("waveform", "Speak a job and it prices itself")
                    benefit("pencil", "Update a rate whenever you need to")
                }
                .padding(.top, 42)
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 24)

                Button {
                    dismiss()
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(colorScheme == .dark ? Color(.homeBackground) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color(.mainText), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .background(Color(.homeBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.homeBackground))
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.body.weight(.medium))
            .foregroundStyle(Color(.mainText))
            .labelStyle(.titleAndIcon)
    }
}

#Preview {
    RateCardIntroSheet {}
}
