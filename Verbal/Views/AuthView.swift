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
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await GoogleAuth.signIn()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
