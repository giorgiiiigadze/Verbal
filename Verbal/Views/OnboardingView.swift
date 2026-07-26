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

            VStack(spacing: 16) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Welcome to Verbal")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Share your thoughts and connect through words.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}
