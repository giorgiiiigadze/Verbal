//
//  ContentView.swift
//  Verbal
//

import SwiftUI

struct ContentView: View {
    @State private var network = NetworkMonitor()
    @State private var session: SessionStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

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

    var body: some View {
        ZStack {
            content
                .environment(session)
                .environment(network)

            if showSplash {
                SplashScreen()
                    .transition(.opacity)
            }

            if !showSplash && !network.isOnline {
                OfflineBanner()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .animation(.spring(duration: 0.4), value: network.isOnline)
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
