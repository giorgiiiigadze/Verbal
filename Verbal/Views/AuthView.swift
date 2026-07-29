//
//  AuthView.swift
//  Verbal
//

import SwiftUI
import GoogleSignInSwift

struct AuthView: View {
    @Environment(SessionStore.self) private var session

    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                    Text("Verbal")
                        .font(.largeTitle.bold())
                    Text("Sign in to continue")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                GoogleSignInButton(action: signInWithGoogle)
                    .frame(maxWidth: .infinity)
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.6 : 1)

                Spacer().frame(height: 8)
            }
            .padding(24)

            if isLoading {
                loadingScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }

    /// Full-screen overlay shown while signing in and setting up the account.
    private var loadingScreen: some View {
        ZStack {
            Color(.homeBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Signing you in…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await GoogleAuth.signIn()
                // Keep the loading screen up — the view is replaced by the app
                // once the session becomes ready (after profile/data preload).
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
