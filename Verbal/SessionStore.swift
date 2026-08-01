//
//  SessionStore.swift
//  Verbal
//

import Foundation
import SwiftUI
import Supabase

@MainActor
@Observable
final class SessionStore {
    enum AppState {
        case loading
        case signedOut
        case ready
    }

    private(set) var state: AppState = .loading
    private(set) var profile: Profile?

    /// The signed-in account's email (from Google auth), for display.
    var email: String? { client.auth.currentUser?.email }

    /// The user's avatar, downloaded and decoded during bootstrap so it shows
    /// instantly (no visible load) once the splash screen dismisses.
    private(set) var avatarImage: Image?
    /// The raw decoded avatar, kept so it can be rendered into a tab-bar icon.
    private(set) var avatarUIImage: UIImage?

    /// True once the initial data needed for first paint has finished loading.
    /// The splash screen stays up until this is true.
    private(set) var isBootstrapped = false

    /// Quotes and rate-card items preloaded during bootstrap so the Home and
    /// Rate Card tabs render instantly with no empty-state flash on first paint.
    private(set) var quotes: [QuoteSummary] = []
    private(set) var rateCard: [RateCardItem] = []
    /// The business profile, preloaded so Settings → Profile shows instantly.
    private(set) var businessProfile: BusinessProfile?
    /// True once the initial fetch of the lists above has completed (success or
    /// failure), so views can tell "still loading" from "genuinely empty".
    private(set) var listsLoaded = false

    /// Update the cached business profile after the user edits it, so reopening
    /// the profile screen reflects the change without a refetch.
    func cacheBusinessProfile(_ profile: BusinessProfile) { businessProfile = profile }

    /// Line items cached per quote so the detail screen renders instantly on open
    /// (populated by prefetching as list rows appear).
    private var lineItemsCache: [UUID: [QuoteLineItem]] = [:]

    /// Cached line items for a quote, if any have been loaded already.
    func lineItems(for quoteID: UUID) -> [QuoteLineItem]? { lineItemsCache[quoteID] }

    /// Store a quote's line items for instant reuse.
    func cacheLineItems(_ items: [QuoteLineItem], for quoteID: UUID) {
        lineItemsCache[quoteID] = items
    }

    /// Fetch and cache a quote's line items unless already cached. Called as list
    /// rows appear so the detail page has them ready before the user taps.
    func prefetchLineItems(for quoteID: UUID) async {
        guard lineItemsCache[quoteID] == nil else { return }
        if let items = try? await QuoteService.fetchLineItems(quoteId: quoteID) {
            lineItemsCache[quoteID] = items
        }
    }

    private let client = SupabaseManager.client
    private let network: NetworkMonitor

    init(network: NetworkMonitor) {
        self.network = network
    }

    /// Resolve the initial state and preload first-paint data, then keep
    /// listening for auth changes.
    func start() async {
        // If a session exists at all, land on the home screen — even if its
        // access token is expired (a logged-in user still has a refresh token)
        // and even if we're offline. Expiry is refreshed in the background; it
        // is NOT a sign-out. We only show sign-in when there is truly no stored
        // session. This avoids a flash of the auth page at cold launch,
        // especially offline where the network state isn't known yet.
        if client.auth.currentSession != nil {
            // Show the app immediately; don't block first paint on the network.
            // The splash dismisses right away (even offline), and the
            // first-paint data streams in via bootstrap() in the background.
            state = .ready
            isBootstrapped = true
            Task { await bootstrap() }
        } else {
            state = .signedOut
            isBootstrapped = true
        }

        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .userUpdated, .tokenRefreshed:
                if change.session != nil {
                    state = .ready
                    await bootstrap()
                }
            case .signedOut:
                // A real sign-out only happens online (user-initiated). A
                // `signedOut` that arrives while offline is almost always a
                // failed background token refresh — keep the user in the app.
                if network.isOnline {
                    clearSession()
                }
            default:
                break
            }
        }
    }

    /// Load everything the first screen needs before it's shown.
    /// Add future home-screen preloads here (feed, etc.).
    private func bootstrap() async {
        await refreshProfile()
        await preloadAvatar()
        await preloadLists()
    }

    /// Load the Home and Rate Card lists up front so those tabs show data
    /// immediately instead of flashing an empty state while fetching.
    func preloadLists() async {
        async let quotesResult = try? await QuoteService.fetchQuotes()
        async let rateResult = try? await QuoteService.fetchRateCard()
        async let bizResult = try? await BusinessService.fetch()
        quotes = await quotesResult ?? quotes
        rateCard = await rateResult ?? rateCard
        businessProfile = await bizResult ?? businessProfile
        listsLoaded = true
    }

    private func clearSession() {
        profile = nil
        avatarImage = nil
        avatarUIImage = nil
        state = .signedOut
    }

    /// Load the current user's profile (name/avatar from Google) for display.
    func refreshProfile() async {
        guard let userID = client.auth.currentUser?.id else { return }
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            self.profile = profile
        } catch {
            // Row may lag right after signup; the greeting just stays generic.
        }
    }

    /// Download and decode the avatar so it's ready before the UI appears.
    private func preloadAvatar() async {
        guard let urlString = profile?.avatarUrl,
              let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                avatarImage = Image(uiImage: image)
                avatarUIImage = image
            }
        } catch {
            // Fall back to the placeholder icon if the download fails.
        }
    }

    // MARK: - Auth actions

    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Record why someone is leaving, before the account goes. Best effort:
    /// feedback must never be the reason a deletion fails.
    func recordDeletionFeedback(reason: String) async {
        struct Feedback: Encodable { let reason: String }
        try? await client
            .from("account_deletion_feedback")
            .insert(Feedback(reason: reason))
            .execute()
    }

    /// Permanently deletes the signed-in account and everything owned by it.
    /// The server derives the user from the caller's token, so this can only
    /// ever delete the current account. Signing out afterwards clears the
    /// local session and returns the app to the auth screen.
    func deleteAccount() async throws {
        let _: DeleteAccountResponse = try await client.functions.invoke("delete-account")
        try? await client.auth.signOut()
    }
}

private struct DeleteAccountResponse: Decodable {
    let deleted: Bool
}
