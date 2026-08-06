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

    /// Keep the cached rate card in step with a list the Rate Card tab just
    /// fetched. Settings reads this to decide whether changing the main
    /// currency would silently redenominate saved prices, so a stale copy here
    /// means that question doesn't get asked.
    func cacheRateCard(_ items: [RateCardItem]) { rateCard = items }

    /// Refetch the rate card after its prices are rewritten elsewhere.
    func refreshRateCard() async {
        if let items = try? await QuoteService.fetchRateCard() { rateCard = items }
    }

    /// Line items cached per quote so the detail screen renders instantly on open
    /// (populated by prefetching as list rows appear).
    private var lineItemsCache: [UUID: [QuoteLineItem]] = [:]

    /// The account everything cached here belongs to, so a switch can be told
    /// apart from an ordinary token refresh.
    private var cachedUserID: UUID?

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
            return
        }
        // Offline. The stored copy is what this quote looked like last time it
        // was read, which beats opening it to an empty table.
        if let cachedUserID,
           let stored = LocalCache.load([QuoteLineItem].self,
                                        for: .lineItems(quoteID: quoteID),
                                        userID: cachedUserID) {
            lineItemsCache[quoteID] = stored
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
            // Restore from disk here, synchronously, before anything renders.
            // Home is built underneath the splash rather than after it, and it
            // copies these lists into its own state the moment it appears — so
            // a restore that lands even a beat later is one it never sees, and
            // the user gets "Couldn't load your quotes" with the quotes sitting
            // on disk. It is a file read; there is nothing to wait for.
            if let userID = client.auth.currentUser?.id {
                cachedUserID = userID
                restoreFromDisk(userID: userID)
            }
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
        // Everything cached below belongs to one account. Signing straight into
        // a second one never emits a signedOut event, so without this check the
        // previous user's business details stay on screen — and print onto the
        // new user's quotes. Refreshes for the same account keep their cache.
        let userID = client.auth.currentUser?.id
        if userID != cachedUserID {
            clearUserData()
        }
        cachedUserID = userID
        if let userID { restoreFromDisk(userID: userID) }

        await refreshProfile()
        await preloadAvatar()
        await preloadLists()
    }

    /// Paint from the last known responses before the network is consulted.
    /// Whatever comes back next replaces them; until it does, the user reads
    /// their own quotes instead of a placeholder or an error.
    private func restoreFromDisk(userID: UUID) {
        if let cached = LocalCache.load([QuoteSummary].self, for: .quotes, userID: userID) {
            quotes = cached
        }
        if let cached = LocalCache.load([RateCardItem].self, for: .rateCard, userID: userID) {
            rateCard = cached
        }
        if let cached = LocalCache.load([BusinessProfile].self, for: .businessProfile, userID: userID) {
            businessProfile = cached.first
        }
        restoreLineItems(userID: userID)
        // Lets the splash stop waiting and Home draw real rows. On a first run
        // there is nothing to restore, so the existing wait still applies.
        if !quotes.isEmpty || !rateCard.isEmpty {
            listsLoaded = true
        }
    }

    /// How many quotes' line items are read before the app is allowed to draw.
    /// About a screenful: enough that anything tappable on arrival is ready.
    private static let eagerLineItemCount = 12

    /// Line items for the restored quotes. Without these the memory cache
    /// starts empty, so the only routes to the stored copy are behind a network
    /// call that has to fail first — and offline that failure is not instant.
    /// The quote opens to an empty table, and the items arrive seconds later or
    /// not at all.
    ///
    /// Only the first screenful is read here. This runs before anything is
    /// drawn, and it is one file read and one decode per quote: fine at ten,
    /// but someone two years into using this has hundreds, and every one of
    /// them would sit between them and their own app at every launch. The rest
    /// follow off the main thread, well before any of them can be scrolled to.
    private func restoreLineItems(userID: UUID) {
        let pending = quotes.map(\.id).filter { lineItemsCache[$0] == nil }
        guard !pending.isEmpty else { return }

        for quoteID in pending.prefix(Self.eagerLineItemCount) {
            if let items = LocalCache.load([QuoteLineItem].self,
                                           for: .lineItems(quoteID: quoteID),
                                           userID: userID) {
                lineItemsCache[quoteID] = items
            }
        }

        let remaining = Array(pending.dropFirst(Self.eagerLineItemCount))
        guard !remaining.isEmpty else { return }
        Task.detached(priority: .utility) {
            var restored: [UUID: [QuoteLineItem]] = [:]
            for quoteID in remaining {
                if let items = LocalCache.load([QuoteLineItem].self,
                                               for: .lineItems(quoteID: quoteID),
                                               userID: userID) {
                    restored[quoteID] = items
                }
            }
            await self.mergeRestoredLineItems(restored)
        }
    }

    /// Fold in what the background read found, leaving alone anything fetched
    /// while it was working — those came from the server and are newer.
    private func mergeRestoredLineItems(_ restored: [UUID: [QuoteLineItem]]) {
        for (quoteID, items) in restored where lineItemsCache[quoteID] == nil {
            lineItemsCache[quoteID] = items
        }
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

        // Off the critical path: the list is already on screen, and this is
        // only worth anything on the launch after next, when there's no signal.
        let ids = quotes.map(\.id)
        Task.detached { await QuoteService.cacheMissingTranscripts(for: ids) }
    }

    private func clearSession() {
        clearUserData()
        state = .signedOut
    }

    /// Drop everything belonging to the account that was signed in. The stale
    /// copies matter beyond being wrong on screen: `preloadLists` falls back to
    /// what it already has when a fetch fails, so anything left here would be
    /// shown as the new user's own data on a flaky connection.
    private func clearUserData() {
        // Wipe the disk copy too, and do it before the id is forgotten. Leaving
        // one account's quotes and client addresses readable on a shared phone
        // is the same leak the in-memory clearing exists to prevent.
        if let cachedUserID { LocalCache.clear(userID: cachedUserID) }
        // "Has had quotes before" describes an account, not a handset. Left set,
        // a brand new account signing in on a phone that has been used before
        // is met by the returning-user card and never sees the one written to
        // explain the app. Cleared here rather than keyed per user because this
        // runs on exactly the two occasions that matter — signing out, and
        // swapping accounts — and a cold launch keeps its own id, so it doesn't.
        UserDefaults.standard.set(false, forKey: "hasEverHadQuotes")
        profile = nil
        avatarImage = nil
        avatarUIImage = nil
        businessProfile = nil
        quotes = []
        rateCard = []
        lineItemsCache = [:]
        listsLoaded = false
        cachedUserID = nil
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
        _ = try? await client
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
