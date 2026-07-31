//
//  OnboardingView.swift
//  Verbal
//
//  First-launch intro shown once before the auth screen.
//

import SwiftUI

struct OnboardingView: View {
    /// Called when the user finishes onboarding.
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 20) {
                Image(.brandMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96)
                    .foregroundStyle(Color(.blueAccentText))
                VStack(spacing: 12) {
                    Text("Speak the job.\nSend the quote.")
                        .font(.robotoSlab(34, relativeTo: .largeTitle))
                        .foregroundStyle(Color(.mainText))
                        .multilineTextAlignment(.center)
                    Text("Describe the work out loud and Verbal turns it into a priced, professional quote in seconds.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.royalBlue600), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.homeBackground))
    }
}
