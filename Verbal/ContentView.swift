//
//  ContentView.swift
//  Verbal
//

import SwiftUI

struct ContentView: View {
    @State private var session = SessionStore()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var minSplashElapsed = false

    /// Show the splash until first-paint data has loaded AND at least 0.5s passed.
    private var showSplash: Bool {
        !session.isBootstrapped || !minSplashElapsed
    }

    var body: some View {
        ZStack {
            content
                .environment(session)

            if showSplash {
                SplashScreen()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .task {
            await session.start()
        }
        .task {
            try? await Task.sleep(for: .seconds(0.5))
            minSplashElapsed = true
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
