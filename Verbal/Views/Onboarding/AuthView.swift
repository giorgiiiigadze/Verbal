//
//  AuthView.swift
//  Verbal
//

import SwiftUI

struct AuthView: View {
    @Environment(SessionStore.self) private var session

    @State private var toast: Toast?
    /// Google's sheet is up. The button waits, but the screen behind it stays
    /// exactly as it was — the user is choosing an account, not signing in.
    @State private var isChoosingAccount = false
    /// Google is done and the work is ours now: token exchange, then the
    /// profile and lists the first screen needs. This is the part worth
    /// covering the screen for.
    @State private var isFinishing = false
    @State private var showAppleComingSoon = false
    @State private var showEmailAuth = false

    var body: some View {
        ZStack {
            AuthBackground()

            VStack(spacing: 0) {
                AuthWelcomeArtwork()
                    .frame(height: 410)
                    .padding(.top, 8)

                Spacer(minLength: 26)

                VStack(alignment: .leading, spacing: 12) {
                    welcomeTitle

                    Text("Sign in to keep your quotes, clients, and work in sync.")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)

                VStack(spacing: 10) {
                    googleButton
                        .disabled(isChoosingAccount)

                    appleButton
                        .disabled(isChoosingAccount)

                    emailButton
                        .disabled(isChoosingAccount)
                }

                authConsent
                    .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            if isFinishing {
                loadingScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isFinishing)
        .preferredColorScheme(.light)
        .toast($toast)
        .navigationDestination(isPresented: $showEmailAuth) {
            EmailAuthView {
                // Order matters: the finishing screen is put up behind the
                // cover before it goes, so the sign-in buttons never flash back
                // into view between the code being accepted and the app
                // appearing.
                toast = nil
                isFinishing = true
                showEmailAuth = false
            }
        }
        .alert("Apple sign-in coming soon", isPresented: $showAppleComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use Google or email for now.")
        }
    }

    private var welcomeTitle: some View {
        HStack(spacing: 10) {
            Text("Welcome to")
            Image(.authAppIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Verbal")
        }
        .font(.system(size: 30, weight: .semibold, design: .default))
        .foregroundStyle(Color(.mainText))
        .minimumScaleFactor(0.72)
        .lineLimit(1)
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
                foreground: .white,
                background: .black,
                border: .white.opacity(0.12),
                isDimmed: isChoosingAccount,
                trailing: isChoosingAccount ? AnyView(ProgressView().tint(.white)) : nil
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

    /// The way in for anyone without a Google account, or unwilling to hand one
    /// over to sign into a quoting app. Quieter than the two above it — it is
    /// the fallback, not the recommendation — so it keeps the card surface
    /// rather than the black capsule.
    private var emailButton: some View {
        Button { showEmailAuth = true } label: {
            Text("Continue with email")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(.mainText))
                .frame(maxWidth: .infinity)
                .frame(height: authButtonHeight)
                .background(Color(.cardSurface), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var authConsent: some View {
        VStack(spacing: 3) {
            Text("By continuing, you agree to Verbal’s")
            HStack(spacing: 4) {
                if let terms = AppInfo.termsURL {
                    Link("Terms of Service", destination: terms)
                        .underline()
                }
                Text("and")
                Link("Privacy Policy", destination: AppInfo.privacyPolicyURL)
                    .underline()
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
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
        HStack(spacing: 10) {
            icon()
                .foregroundStyle(foreground)
                .frame(width: authButtonIconSize, height: authButtonIconSize)
                .opacity(isDimmed ? 0.35 : 1)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foreground)
                .opacity(isDimmed ? 0.35 : 1)

            if let trailing { trailing }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, authButtonHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: authButtonHeight)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
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
        toast = nil
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
                    toast = Toast(style: .error, message: googleSignInErrorMessage(error))
                }
            }
        }
    }

    /// Provider error strings are written for logs and can be bare OAuth codes
    /// such as `access_denied`. Keep that implementation detail out of the
    /// sign-in screen while still giving the person a useful next step.
    private func googleSignInErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("access_denied") || message.contains("access denied") {
            return "Google sign-in was denied. Try another account."
        }
        return "Couldn't sign in with Google. Try again."
    }
}

/// A light, floating product collage in the spirit of a cover-art spread. The
/// tiles use Verbal concepts rather than another product's artwork, and can be
/// replaced independently if final imagery is added later.
private struct AuthWelcomeArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                AuthArtworkTile(kind: .voice)
                    .rotationEffect(.degrees(-11))
                    .position(x: width * 0.09, y: height * 0.10)

                AuthArtworkTile(kind: .quote)
                    .rotationEffect(.degrees(5))
                    .position(x: width * 0.5, y: height * 0.10)

                AuthArtworkTile(kind: .sent)
                    .rotationEffect(.degrees(8))
                    .position(x: width * 0.91, y: height * 0.10)

                AuthArtworkTile(kind: .rate)
                    .rotationEffect(.degrees(-6))
                    .position(x: width * 0.5, y: height * 0.48)

                AuthArtworkTile(kind: .client)
                    .rotationEffect(.degrees(7))
                    .position(x: width * 0.15, y: height * 0.65)

                AuthArtworkTile(kind: .visit)
                    .rotationEffect(.degrees(-8))
                    .position(x: width * 0.85, y: height * 0.68)

                AuthArtworkTile(kind: .draft)
                    .rotationEffect(.degrees(-5))
                    .position(x: width * 0.31, y: height * 0.91)

                AuthArtworkTile(kind: .accepted)
                    .rotationEffect(.degrees(9))
                    .position(x: width * 0.75, y: height * 0.94)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct AuthArtworkTile: View {
    let kind: AuthArtworkKind

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [kind.background.opacity(0.88), kind.background],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 82, height: 82)
            .overlay {
                content
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(kind.foreground)
            }
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.16), .clear, .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.11), radius: 8, y: 4)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .voice:
            tileContent(icon: .onboardingSpeak, value: "0:42", label: "VOICE NOTE")

        case .quote:
            tileContent(icon: .quoteDocument, value: "£2,450", label: "DRAFT QUOTE",
                        valueSize: 14)

        case .client:
            tileContent(icon: .clientList, value: "Sarah", label: "CLIENT")

        case .rate:
            tileContent(icon: .rateCardIntroTag, value: "£65", label: "PER HOUR")

        case .visit:
            tileContent(icon: .visitClock, value: "10:30", label: "TUE · VISIT",
                        valueSize: 14)

        case .sent:
            tileContent(icon: .onboardingSend, value: "Sent", label: "QUOTE")

        case .draft:
            tileContent(icon: .recordingIntroReview, value: "3 items", label: "DRAFT",
                        valueSize: 13)

        case .accepted:
            tileContent(icon: .shareSketch, value: "Accepted", label: "QUOTE",
                        valueSize: 12)
        }
    }

    private func tileContent(icon: ImageResource, value: String, label: String,
                             valueSize: CGFloat = 15) -> some View {
        VStack(spacing: 3) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 23, height: 23)

            Text(value)
                .font(.system(size: valueSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.system(size: 6.5, weight: .bold))
                .tracking(0.45)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private enum AuthArtworkKind {
    case voice, quote, client, rate, visit, sent, draft, accepted

    var background: Color {
        switch self {
        case .voice: Color(red: 0.14, green: 0.32, blue: 0.82)
        case .quote: Color(red: 1.00, green: 0.93, blue: 0.70)
        case .client: Color(red: 1.00, green: 0.55, blue: 0.48)
        case .rate: Color(red: 0.97, green: 0.84, blue: 0.27)
        case .visit: Color(red: 0.70, green: 0.90, blue: 0.78)
        case .sent: Color(red: 0.82, green: 0.75, blue: 1.00)
        case .draft: Color(red: 0.63, green: 0.83, blue: 1.00)
        case .accepted: Color(red: 0.07, green: 0.37, blue: 0.35)
        }
    }

    var foreground: Color {
        switch self {
        case .voice, .accepted: .white
        default: Color(red: 0.08, green: 0.09, blue: 0.12)
        }
    }
}

#Preview("Auth") {
    let network = NetworkMonitor()
    return AuthView()
        .environment(SessionStore(network: network))
        .environment(network)
}
