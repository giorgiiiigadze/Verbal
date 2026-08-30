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

                appleButton
                    .disabled(isChoosingAccount)

                googleButton
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

    private let authButtonHeight: CGFloat = 56
    private let authButtonHorizontalPadding: CGFloat = 22
    private let authButtonIconSize: CGFloat = 20

    /// Google's own mark, from the SDK's resources, on the app's own button —
    /// the SDK's stock control can't take the shape the rest of the app uses.
    /// Both provider buttons go through the same shell so their width, height,
    /// padding and icon slot stay identical.
    private var googleButton: some View {
        Button(action: signInWithGoogle) {
            authButtonLabel(
                title: "Continue with Google",
                foreground: .black,
                background: .white,
                border: Color.black.opacity(0.12),
                isDimmed: isChoosingAccount,
                trailing: isChoosingAccount ? AnyView(ProgressView().tint(.black)) : nil
            ) {
                Image(.googleLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: authButtonIconSize, height: authButtonIconSize)
            }
        }
        .buttonStyle(.plain)
    }

    private var appleButton: some View {
        Button {
            showAppleComingSoon = true
        } label: {
            authButtonLabel(
                title: "Continue with Apple",
                foreground: .white,
                background: .black,
                border: .white.opacity(0.12)
            ) {
                Image(systemName: "apple.logo")
                    .font(.system(size: authButtonIconSize, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue with Apple, coming soon")
    }

    private func authButtonLabel<Icon: View>(
        title: String,
        foreground: Color,
        background: Color,
        border: Color,
        isDimmed: Bool = false,
        trailing: AnyView? = nil,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        ZStack {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(foreground)
                .opacity(isDimmed ? 0.35 : 1)

            HStack {
                icon()
                    .foregroundStyle(foreground)
                    .frame(width: authButtonIconSize, height: authButtonIconSize)
                    .opacity(isDimmed ? 0.35 : 1)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
        }
        .padding(.horizontal, authButtonHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: authButtonHeight)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 0.5))
    }

    /// Full-screen overlay shown while signing in and setting up the account.
    private var loadingScreen: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ProgressView()
                .controlSize(.regular)
                .tint(.primary)
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
