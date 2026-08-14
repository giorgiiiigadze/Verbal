//
//  ContentView.swift
//  Verbal
//

import SwiftUI

struct ContentView: View {
    @State private var network = NetworkMonitor()
    @State private var session: SessionStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

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
                OfflineBanner()
                    // Arrives from below, but doesn't leave the same way — a
                    // banner sliding back down reads as being dropped. Going
                    // out it eases off: shrinks a little, drifts down a touch,
                    // and fades, so it settles away instead of vanishing.
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.94)
                            .combined(with: .offset(y: 14))
                            .combined(with: .opacity)
                    ))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    // Says its piece and leaves. Being told you're offline is
                    // worth knowing once; sitting over the app for as long as
                    // the signal is gone is just a thing in the way, and the
                    // app is built to keep working without a connection.
                    //
                    // Tied to the banner's own lifetime, so coming back online
                    // cancels it rather than leaving a timer to fire into
                    // nothing.
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        // Slower going than coming, and no bounce: a spring
                        // would draw the eye back to something that is on its
                        // way out.
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
                OnboardingView { hasSeenOnboarding = true }
            }
        case .ready:
            MainTabView()
        }
    }
}

#Preview {
    ContentView()
}
