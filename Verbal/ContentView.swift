//
//  ContentView.swift
//  Verbal
//

import SwiftUI

struct ContentView: View {
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.system.rawValue
    @State private var network = NetworkMonitor()
    @State private var session: SessionStore
    /// What they're entitled to. Owned here rather than by the tab view so the
    /// `Transaction.updates` listener is running from launch — a renewal or a
    /// refund arrives when Apple sends it, not when a screen happens to be up.
    @State private var store = Store()
    /// Whether this device has finished the post-registration setup — read
    /// from the Keychain, not `@AppStorage`, so returning users do not repeat
    /// it after signing out or reinstalling. See `OnboardingMemory`.
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

    /// The banner belongs to the signed-in app proper. Onboarding is a focused
    /// setup flow, so an offline warning there would interrupt the task — and
    /// its bottom inset is measured against a tab bar that only exists once
    /// setup is complete.
    private var showsOfflineBanner: Bool {
        session.state == .ready
            && !showSplash
            && !network.isOnline
            && !offlineBannerDismissed
    }

    /// Authentication and the signed-in app both follow the saved appearance
    /// preference. This must live at the scene root so every entry screen uses
    /// the same light, dark, or system setting.
    private var preferredColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearance) ?? .system).colorScheme
    }

    var body: some View {
        ZStack {
            content

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
                .padding(.top, 50)
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
        .environment(session)
        .environment(network)
        .environment(store)
        .preferredColorScheme(preferredColorScheme)
        .animation(.easeInOut(duration: 0.35), value: showSplash)
        .animation(.spring(duration: 0.4), value: network.isOnline)
        .onAppear {
            AppNotificationRouter.shared.isReadyForDeepLinkPresentation = !showSplash
        }
        .onChange(of: showSplash) { _, isShowingSplash in
            AppNotificationRouter.shared.isReadyForDeepLinkPresentation = !isShowingSplash
        }
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
        // can briefly use an outdated completion state.
        .onChange(of: session.state) { _, state in
            hasSeenOnboarding = OnboardingMemory.hasSeenOnboarding
            // Report the entitlement against whoever just signed in. StoreKit's
            // answer belongs to the device and doesn't change here; the profile
            // it has to be written onto does. Without this a subscriber signing
            // into a second account looks unsubscribed to the server, and gets
            // held to the free tier on a phone that has plainly paid.
            if state == .ready {
                Task { await store.refreshEntitlement() }
            }
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
            NavigationStack {
                AuthView()
            }
        case .ready:
            if !hasSeenOnboarding {
                OnboardingView {
                    OnboardingMemory.hasSeenOnboarding = true
                    hasSeenOnboarding = true
                }
            } else {
                MainTabView()
            }
        }
    }
}

#Preview {
    ContentView()
}
