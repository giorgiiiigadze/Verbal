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

    /// The business logo, decoded once and held so the profile screen and the
    /// PDF letterhead both draw it without a download each time.
    private(set) var businessLogo: UIImage?

    /// Update the cached business profile after the user edits it, so reopening
    /// the profile screen reflects the change without a refetch.
    func cacheBusinessProfile(_ profile: BusinessProfile) { businessProfile = profile }

    /// Show a just-picked logo everywhere at once, before it has been uploaded.
    /// The upload is the slow part and the user has already seen their choice;
    /// making the screen wait for a round trip to agree with them is what makes
    /// an app feel like a form rather than a tool.
    func cacheBusinessLogo(_ image: UIImage?) {
        businessLogo = image
        guard let cachedUserID else { return }
        if let data = image?.pngData() {
            LocalCache.save(data, for: .businessLogo, userID: cachedUserID)
        } else {
            LocalCache.clear(key: .businessLogo, userID: cachedUserID)
        }
    }

    /// Fetch the logo named by the profile, unless the bytes on disk are already
    /// the ones it names. The URL is stored alongside the image so a later
    /// launch can tell "same logo, don't re-download" from "they changed it".
    private func refreshBusinessLogo() async {
        guard let cachedUserID else { return }
        guard let urlString = businessProfile?.logoUrl, let url = URL(string: urlString) else {
            // The profile names no logo: drop whatever is held, or one the user
            // removed keeps printing on quotes from this device.
            if businessLogo != nil { cacheBusinessLogo(nil) }
            return
        }
        // Every upload writes a fresh filename, so an unchanged URL means
        // unchanged bytes.
        if UserDefaults.standard.string(forKey: Self.logoURLKey) == urlString,
           businessLogo != nil { return }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        businessLogo = image
        LocalCache.save(data, for: .businessLogo, userID: cachedUserID)
        UserDefaults.standard.set(urlString, forKey: Self.logoURLKey)
    }

    private static let logoURLKey = "cachedBusinessLogoURL"

    /// Keep the cached rate card in step with a list the Rate Card tab just
    /// fetched. Settings reads this to decide whether changing the main
    /// currency would silently redenominate saved prices, so a stale copy here
    /// means that question doesn't get asked.
    func cacheRateCard(_ items: [RateCardItem]) { rateCard = items }

    /// Prices spoken into recent quotes, as fetched — before any of them are
    /// measured against the rate card.
    ///
    /// Kept raw on purpose. The offer is which of these aren't saved yet, and
    /// that answer changes the moment a rate is added or deleted; derived here
    /// it re-answers itself, where a stored list would keep offering a price the
    /// user just accepted.
    private(set) var spokenPrices: [RateCandidate] = []

    var rateCandidates: [RateCandidate] {
        spokenPrices.filter { candidate in
            !rateCard.contains { $0.looksLike(candidate.name) }
        }
    }

    func cacheSpokenPrices(_ prices: [RateCandidate]) { spokenPrices = prices }

    // MARK: - Free allowance

    /// Quotes a day without a subscription.
    static let freeQuotesPerDay = 2

    /// Quotes made since local midnight, counted on the server. Nil until the
    /// first count comes back — the difference matters, because zero means the
    /// full allowance and nil means we don't know yet, and nothing should be
    /// refused on the strength of not knowing.
    private(set) var quotesUsedToday: Int?

    var freeQuotesRemaining: Int? {
        quotesUsedToday.map { max(Self.freeQuotesPerDay - $0, 0) }
    }

    /// The user's own midnight, not UTC's. A day that rolls over at 4am because
    /// of where the phone is would be indefensible to explain to someone whose
    /// allowance vanished mid-afternoon.
    func refreshQuoteUsage() async {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        if let used = try? await QuoteService.quotesUsed(since: startOfDay) {
            quotesUsedToday = used
        }
    }

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

    /// Drop a deleted quote from the shared list and its cached line items.
    ///
    /// The Clients tab is drawn straight off `quotes`, so a delete that only
    /// updated the screen it happened on left the quote — and any client it was
    /// the last of — standing there. Removing it here is what makes it leave.
    func removeQuote(id: UUID) {
        quotes.removeAll { $0.id == id }
        lineItemsCache[id] = nil
    }

    /// Apply an edit to the shared copy of a quote.
    ///
    /// Every screen drawn from `quotes` — the Clients tab, its threads, a
    /// client's page, the outstanding band — sees it at once. Before this, the
    /// quote screen kept each field in its own state, wrote to the server and
    /// told nobody, so a status changed there was still the old one on the tab
    /// next door until something refetched. Home papered over its half with a
    /// callback per field, which is the same fix written once per screen that
    /// asks for it.
    ///
    /// Takes a closure rather than one method per field: the fields differ, the
    /// plumbing doesn't.
    func updateQuote(id: UUID, _ edit: (inout QuoteSummary) -> Void) {
        guard let index = quotes.firstIndex(where: { $0.id == id }) else { return }
        edit(&quotes[index])
    }

    /// Replace the shared list with a freshly fetched one. `quotes` is otherwise
    /// only set at launch, so a quote made afterwards never reached the Clients
    /// tab until the next cold start. Home fetches the authoritative list on
    /// every load — including right after a recording — so it hands the result
    /// here to keep the tab drawn from it current.
    func setQuotes(_ quotes: [QuoteSummary]) {
        self.quotes = quotes
    }

    /// Re-read the quote list and publish it, for screens that own no copy of
    /// their own. The Clients tab is drawn entirely from `quotes`, so rather
    /// than trusting whichever screen ran last to have refreshed it, that tab
    /// asks for itself every time it appears.
    ///
    /// A failed read leaves the list alone: what is on screen came from the
    /// server too, and blanking a tab because one fetch missed is worse than
    /// showing a list that is a minute old.
    func refreshQuotes() async {
        if let fresh = try? await QuoteService.fetchQuotes() {
            quotes = fresh
        }
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
    private var isExplicitlySigningOut = false

    /// Booked visits, and the sync that keeps them and `scheduled_visits` in
    /// step. Owned here because the two things that decide whose visits these
    /// are — a sign-out and a swap to another account — both happen here.
    let visitStore: VisitStore

    init(network: NetworkMonitor) {
        self.network = network
        self.visitStore = VisitStore(network: network)
    }

    /// Restore a stored session synchronously enough for launch decisions.
    private func restoreStoredSessionForLaunch() -> Bool {
        guard client.auth.currentSession != nil else { return false }

        // Restore from disk here, synchronously, before anything renders.
        // Home is built underneath the splash rather than after it, and it
        // copies these lists into its own state the moment it appears.
        if let userID = client.auth.currentUser?.id {
            cachedUserID = userID
            restoreFromDisk(userID: userID)
        }

        // Show the app immediately; don't block first paint on the network.
        state = .ready
        isBootstrapped = true
        markOnboardingSeen()
        Task { await bootstrap() }
        return true
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
        if !restoreStoredSessionForLaunch() {
            // On some cold launches the Supabase client has not surfaced the
            // Keychain session on the first synchronous read. Give it one short
            // turn before deciding the user is actually signed out.
            try? await Task.sleep(for: .milliseconds(350))
            if !restoreStoredSessionForLaunch() {
                state = .signedOut
                isBootstrapped = true
            }
        }

        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .userUpdated, .tokenRefreshed:
                if change.session != nil {
                    state = .ready
                    markOnboardingSeen()
                    await bootstrap()
                }
            case .signedOut:
                // Supabase can surface signed-out during launch or a token
                // refresh before the stored session has settled. Only the app's
                // own sign-out/delete flows should clear local state and send
                // the user back to auth.
                if isExplicitlySigningOut {
                    isExplicitlySigningOut = false
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
        // Both read the business profile the preload just fetched.
        await adoptPendingTrade()
        // After the trade, which may be what creates the profile row this then
        // writes into.
        await adoptOnboardingDraft()
        await refreshBusinessLogo()
    }

    /// Records that this person has been through onboarding, the moment a
    /// session turns up.
    ///
    /// Belt and braces alongside the flow writing it at the end: someone whose
    /// account already exists has plainly been through it, however they got
    /// here — a reinstall that restored the Keychain session, or a sign-in on
    /// a device that has never shown them the flow.
    private func markOnboardingSeen() {
        OnboardingMemory.hasSeenOnboarding = true
    }

    /// Onboarding runs before there is an account, so the trade it collects has
    /// to wait on the device until one exists. Written once and then forgotten,
    /// so a user who later clears it in their profile doesn't find it restored
    /// on the next launch.
    private func adoptPendingTrade() async {
        let pending = UserDefaults.standard.string(forKey: Self.pendingTradeKey)
        guard let pending, !pending.isEmpty else { return }
        var profile = businessProfile ?? .empty
        // Never overwrite a trade the account already has: the phone's answer
        // is older than anything the user has since typed on another device.
        if profile.trade?.isEmpty == false {
            UserDefaults.standard.removeObject(forKey: Self.pendingTradeKey)
            return
        }
        profile.trade = pending
        guard (try? await BusinessService.save(profile)) != nil else { return }
        businessProfile = profile
        UserDefaults.standard.removeObject(forKey: Self.pendingTradeKey)
    }

    /// The rest of what onboarding collected: business name, tax rate, and the
    /// prices ticked off the trade's list.
    ///
    /// Same terms as the trade above — never overwrite what the account already
    /// has, since a second device's answer is older than anything typed since,
    /// and clear the draft either way so an emptied field doesn't come back.
    private func adoptOnboardingDraft() async {
        guard let draft = OnboardingDraft.load() else { return }
        defer { OnboardingDraft.clear() }

        var profile = businessProfile ?? .empty
        var changed = false
        if let name = draft.businessName, !name.isEmpty,
           (profile.businessName ?? "").isEmpty {
            profile.businessName = name
            changed = true
        }
        if let rate = draft.taxRate, profile.defaultTaxRate == 0 {
            profile.defaultTaxRate = rate
            changed = true
        }
        if changed, (try? await BusinessService.save(profile)) != nil {
            businessProfile = profile
        }

        // Only onto an empty card. A rate card with anything in it belongs to a
        // user who has already been here, and their prices beat a phone's memory
        // of what they tapped before signing in.
        guard !draft.rates.isEmpty, rateCard.isEmpty else { return }
        for rate in draft.rates {
            try? await QuoteService.addRateCardItem(
                name: rate.name, unit: rate.unit,
                unitPrice: rate.price, type: rate.type)
        }
        await refreshRateCard()
    }

    private static let pendingTradeKey = "pendingTrade"

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
        if let data = LocalCache.loadData(for: .businessLogo, userID: userID) {
            businessLogo = UIImage(data: data)
        }
        // Who they are, restored with everything else they own. Without this a
        // launch with no signal showed a stranger's placeholder on the one
        // screen that is meant to be theirs.
        if let cached = LocalCache.load(Profile.self, for: .profile, userID: userID) {
            profile = cached
        }
        if let data = LocalCache.loadData(for: .avatar, userID: userID),
           let image = UIImage(data: data) {
            avatarImage = Image(uiImage: image)
            avatarUIImage = image
        }
        // Read straight off the disk, like everything above it, so Upcoming has
        // its rows on the first frame instead of after a fetch.
        visitStore.attach(userID: userID)
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
        // Fetched beside the rate card, not after it. The offer needs both, but
        // only the comparison does — asking for one and then the other would put
        // a second round trip in front of the tab for no gain.
        async let spokenResult = try? await QuoteService.recentSpokenPrices()
        // Known before the user can reach the mic, so the allowance is never
        // being counted while they're already talking.
        async let usageResult = try? await QuoteService.quotesUsed(
            since: Calendar.current.startOfDay(for: .now))
        quotes = await quotesResult ?? quotes
        rateCard = await rateResult ?? rateCard
        businessProfile = await bizResult ?? businessProfile
        spokenPrices = await spokenResult ?? spokenPrices
        quotesUsedToday = await usageResult ?? quotesUsedToday
        listsLoaded = true

        // Off the critical path: the list is already on screen, and this is
        // only worth anything on the launch after next, when there's no signal.
        let ids = quotes.map(\.id)
        Task.detached { await QuoteService.cacheMissingTranscripts(for: ids) }

        // Also off the critical path: Upcoming is already on screen from the
        // cache. This is what pushes a visit booked with no signal, and pulls
        // one booked on another phone.
        Task { await visitStore.sync() }
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
        businessLogo = nil
        // Keyed to nothing in particular, so it has to go with the account or
        // the next user's logo is judged "unchanged" against the last one's URL
        // and never downloaded.
        UserDefaults.standard.removeObject(forKey: Self.logoURLKey)
        // Same reason: left behind, the next user's avatar is judged
        // "unchanged" against the last one's URL and never downloaded.
        UserDefaults.standard.removeObject(forKey: Self.avatarURLKey)
        // Booked visits are client names with dates on them, and they belong to
        // the account rather than the handset. The server holds them now, so
        // this is a wipe and not a deletion: account B sees an empty Upcoming,
        // and account A gets every visit back when they sign in again. Anything
        // that never reached the server is kept under its own account's id and
        // pushed at that account's next sign-in.
        //
        // The reminders go regardless — account B must never be buzzed about
        // somebody else's Mrs. Patel.
        ScheduledVisitNotifications.cancelAll(visits: visitStore.visits)
        visitStore.detach(preservingPending: true)
        quotes = []
        rateCard = []
        spokenPrices = []
        quotesUsedToday = nil
        lineItemsCache = [:]
        listsLoaded = false
        cachedUserID = nil
    }

    /// Load the current user's profile (name/avatar from Google) for display.
    func refreshProfile() async {
        guard let userID = client.auth.currentUser?.id else { return }
        do {
            let response: PostgrestResponse<Profile> = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
            profile = response.value
            // Kept for the same reason the business profile is: offline this is
            // the only thing that knows the user's name, and the URL of their
            // face.
            LocalCache.save(response.data, for: .profile, userID: userID)
        } catch {
            // Row may lag right after signup, and offline this always fails.
            // Whatever was restored from disk stays put rather than being
            // replaced with nothing.
        }
    }

    /// Download and decode the avatar so it's ready before the UI appears.
    ///
    /// Skipped when the bytes on disk already belong to the URL the profile
    /// names. Bootstrap runs on every token refresh as well as at launch, so
    /// without this the same picture is fetched and decoded again every few
    /// hours for as long as the app is open.
    private func preloadAvatar() async {
        guard let userID = cachedUserID,
              let urlString = profile?.avatarUrl,
              let url = URL(string: urlString) else { return }
        if UserDefaults.standard.string(forKey: Self.avatarURLKey) == urlString,
           avatarUIImage != nil { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                avatarImage = Image(uiImage: image)
                avatarUIImage = image
                LocalCache.save(data, for: .avatar, userID: userID)
                UserDefaults.standard.set(urlString, forKey: Self.avatarURLKey)
            }
        } catch {
            // Keep whatever was restored from disk; the placeholder is only for
            // a user who has never been online with this account.
        }
    }

    private static let avatarURLKey = "cachedAvatarURL"

    // MARK: - Auth actions

    func signOut() async throws {
        // While the token still works. Afterwards there is no session to write
        // with, so a visit booked in a basement this morning would sit on the
        // phone until this account next signs in.
        await visitStore.flushPending()
        isExplicitlySigningOut = true
        do {
            try await client.auth.signOut()
            clearSession()
            isExplicitlySigningOut = false
        } catch {
            isExplicitlySigningOut = false
            throw error
        }
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
        // Nothing left to push to: the rows went with the account. Dropped
        // before `clearSession`, so the sign-out below doesn't try to preserve
        // work for a user that no longer exists.
        visitStore.detach(preservingPending: false)
        // Forget that they were ever onboarded. Signing out deliberately does
        // not do this — leaving is not forgetting — but deleting the account
        // is the one place someone says so outright, and whoever signs up on
        // this phone next is starting from nothing.
        OnboardingMemory.erase()
        isExplicitlySigningOut = true
        try? await client.auth.signOut()
        clearSession()
        isExplicitlySigningOut = false
    }
}

private struct DeleteAccountResponse: Decodable {
    let deleted: Bool
}
