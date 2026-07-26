//
//  ContentView.swift
//  Verbal
//

import SwiftUI

struct ContentView: View {
    @State private var session = SessionStore()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
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
        .environment(session)
        .task {
            await session.start()
        }
    }
}

#Preview {
    ContentView()
}
