//
//  AuthView.swift
//  Verbal
//

import SwiftUI

struct AuthView: View {
    @Environment(SessionStore.self) private var session

    @State private var errorMessage: String?
    /// Google's sheet is up. The button waits, but the screen behind it stays
    /// exactly as it was — the user is choosing an account, not signing in.
    @State private var isChoosingAccount = false
    /// Google is done and the work is ours now: token exchange, then the
    /// profile and lists the first screen needs. This is the part worth
    /// covering the screen for.
    @State private var isFinishing = false
    @State private var headlineIndex = 0
    @State private var showAppleComingSoon = false

    var body: some View {
        ZStack {
            AuthBackground()

            VStack(spacing: 24) {
                // The real mark, not a stand-in glyph. This is the first screen
                // of the app and it was wearing an SF Symbol.
                HStack(spacing: 10) {
                    Image(.brandMark)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28)
                        .foregroundStyle(Color(.blueAccentText))
                    Text("Verbal")
                        .font(.robotoSlab(26, relativeTo: .title2))
                        .foregroundStyle(Color(.blueAccentText))
                }
                .padding(.top, 8)

                Spacer()

                Text(Self.headlines[headlineIndex])
                    .font(.robotoSlab(32, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)
                    .id(headlineIndex)
                    // Rises in as the last one lifts away. Deliberately not the
                    // banner's push: that travels a full line height and would
                    // need clipping to a fixed frame, which is what cost the mic
                    // sheet its icon at the larger type sizes.
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 14)),
                        removal: .opacity.combined(with: .offset(y: -14))
                    ))
                    .task { await cycleHeadlines() }

                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                googleButton
                    .disabled(isChoosingAccount)

                appleButton
                    .disabled(isChoosingAccount)

                Spacer().frame(height: 8)
            }
            .padding(24)

            if isFinishing {
                loadingScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isFinishing)
        .alert("Apple sign-in coming soon", isPresented: $showAppleComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use Google for now.")
        }
    }

    /// One promise, said four ways. Not a carousel of different claims — a
    /// sign-in screen that argues a new point every few seconds reads as an
    /// advert, and this one is being looked at by someone who has already
    /// decided to install.
    private static let headlines = [
        "Speak the job.\nSend the quote.",
        "Describe the work.\nWalk out with it priced.",
        "Say it once.\nThe quote writes itself.",
        "Talk through the job.\nLeave with it quoted."
    ]

    /// Slow on purpose. The generating banner turns over every 1.8 seconds
    /// because something is actually happening; here nothing is, and text that
    /// changes while it is being read is worse than text that doesn't move.
    private func cycleHeadlines() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                headlineIndex = (headlineIndex + 1) % Self.headlines.count
            }
        }
    }

    /// Google's own mark, from the SDK's resources, on the app's own button —
    /// the SDK's stock control can't take the shape the rest of the app uses.
    /// The logo sits at the leading edge with the label centred in the full
    /// width, so a second provider added later stacks under it and lines up.
    private var googleButton: some View {
        Button(action: signInWithGoogle) {
            ZStack {
                Text("Continue with Google")
                    .font(.body.weight(.semibold))
                    // The button is white in both appearances, so the label and
                    // spinner are pinned dark rather than following the scheme.
                    .foregroundStyle(.black)
                    .opacity(isChoosingAccount ? 0.35 : 1)
                HStack {
                    Image(.googleLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .opacity(isChoosingAccount ? 0.35 : 1)
                    Spacer(minLength: 0)
                    if isChoosingAccount {
                        ProgressView().tint(.black)
                    }
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var appleButton: some View {
        Button {
            showAppleComingSoon = true
        } label: {
            ZStack {
                Text("Continue with Apple")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                HStack {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.black, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue with Apple, coming soon")
    }

    /// Full-screen overlay shown while signing in and setting up the account.
    /// Uses the brand mark rather than a spinner, so this reads as a
    /// continuation of the splash instead of a system wait.
    private var loadingScreen: some View {
        ZStack {
            Color(.homeBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(.brandMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88)
                    .foregroundStyle(Color(.blueAccentText))
                    .shimmer(active: true, highlight: .white)
                Text("Signing you in…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func signInWithGoogle() {
        isChoosingAccount = true
        errorMessage = nil
        Task {
            do {
                try await GoogleAuth.signIn {
                    // Google has finished; the wait is ours from here.
                    isChoosingAccount = false
                    isFinishing = true
                }
                // The loading screen stays up deliberately: this view is
                // replaced once the session is ready, after the preload, so
                // there is no gap between it and the app.
            } catch {
                isChoosingAccount = false
                isFinishing = false
                // Backing out of Google's sheet is a decision, not a failure.
                // Saying "the user canceled the sign-in flow" in red tells
                // someone their own choice went wrong.
                if !GoogleAuth.isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview("Auth") {
    let network = NetworkMonitor()
    return AuthView()
        .environment(SessionStore(network: network))
        .environment(network)
}
