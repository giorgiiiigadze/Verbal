//
//  ContentView.swift
//  Verbal
//

import SwiftUI

struct ContentView: View {
    @State private var network = NetworkMonitor()
    @State private var session: SessionStore
    /// Whether this person has been through onboarding — read from the
    /// Keychain, not `@AppStorage`, so it survives a delete and reinstall the
    /// same way the auth session does. See `OnboardingMemory`.
    ///
    /// Mirrored into state because the Keychain is not observable: the flow
    /// itself writes through `OnboardingMemory` and then flips this, which is
    /// what moves the screen on.
    @State private var hasSeenOnboarding = OnboardingMemory.hasSeenOnboarding

    /// Set when the user swipes the offline banner away. Cleared on reconnect,
    /// so dismissing one drop-out doesn't silence the next one.
    @State private var offlineBannerDismissed = false

    @State private var minSplashElapsed = false
    /// Caps how long the splash will wait for the preloaded lists, so a slow
    /// or offline launch still reaches the app promptly.
    @State private var listWaitElapsed = false

    init() {
        let network = NetworkMonitor()
        _network = State(initialValue: network)
        _session = State(initialValue: SessionStore(network: network))
    }

    /// Show the splash until first-paint data has loaded AND at least 0.5s passed.
    ///
    /// For a signed-in launch it also waits (briefly) on the preloaded quote
    /// and rate-card lists: `isBootstrapped` turns true before those fetches
    /// finish, so dismissing on it alone let Home paint an empty screen for a
    /// moment. The wait is capped by `listWaitElapsed` so a slow or offline
    /// start still gets in.
    private var showSplash: Bool {
        guard session.isBootstrapped, minSplashElapsed else { return true }
        return session.state == .ready && !session.listsLoaded && !listWaitElapsed
    }

    /// The banner belongs to the signed-in app. Onboarding runs entirely on a
    /// local draft and needs no connection, so a banner there interrupts a flow
    /// that has nothing to fail — and its bottom inset is measured against a tab
    /// bar that only exists once you're in.
    private var showsOfflineBanner: Bool {
        session.state == .ready
            && !showSplash
            && !network.isOnline
            && !offlineBannerDismissed
    }

    var body: some View {
        ZStack {
            content
                .environment(session)
                .environment(network)

            if showSplash {
                SplashScreen()
                    .transition(.opacity)
            }

            if showsOfflineBanner {
                OfflineBanner {
                    withAnimation(.smooth(duration: 0.3)) {
                        offlineBannerDismissed = true
                    }
                }
                .padding(.top, 28)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.96)
                        .combined(with: .offset(y: -10))
                        .combined(with: .opacity)
                ))
                .frame(maxHeight: .infinity, alignment: .top)
                // Says its piece and leaves. Being told you're offline is worth
                // knowing once; sitting over the app for as long as the signal
                // is gone is just a thing in the way, and the app is built to
                // keep working without a connection.
                .task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.45)) {
                        offlineBannerDismissed = true
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .animation(.spring(duration: 0.4), value: network.isOnline)
        .onChange(of: network.isOnline) { _, isOnline in
            // Re-arm on reconnect: the next time the signal goes, that's news
            // again and worth saying.
            if isOnline { offlineBannerDismissed = false }
        }
        .task {
            await session.start()
        }
        // Signing out is the one moment the mirror above can be stale: the
        // session that `SessionStore` recorded arrived after this view read
        // the Keychain, so without this a sign-out inside a reinstalled app
        // drops back to onboarding rather than to sign-in.
        .onChange(of: session.state) { _, _ in
            hasSeenOnboarding = OnboardingMemory.hasSeenOnboarding
        }
        .task {
            try? await Task.sleep(for: .seconds(0.5))
            minSplashElapsed = true
        }
        .task {
            try? await Task.sleep(for: .seconds(2.0))
            listWaitElapsed = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .loading:
            Color.clear
        case .signedOut:
            if hasSeenOnboarding {
                AuthView()
            } else {
                OnboardingView {
                    OnboardingMemory.hasSeenOnboarding = true
                    hasSeenOnboarding = true
                }
            }
        case .ready:
            MainTabView()
        }
    }
}

#Preview {
    ContentView()
}
