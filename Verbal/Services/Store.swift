//
//  Store.swift
//  Verbal
//
//  What the user is entitled to, and the one flag that raises the paywall.
//
//  `isPro` is derived from StoreKit on every refresh rather than stored
//  anywhere. A cached boolean is a subscription that survives its own
//  cancellation — and, on the other side, a paid user locked out because a
//  local flag went missing. `Transaction.currentEntitlements` is the only
//  thing that actually knows, so it is asked every time.
//
//  Held for the life of the app: the `Transaction.updates` listener has to be
//  running before a renewal, refund or revocation arrives, and those arrive
//  whenever Apple says so rather than while a particular screen is up.
//

import Foundation
import StoreKit
import Supabase

@MainActor
@Observable
final class Store {
    /// Fixed now so App Store Connect can be made to match them later. Nothing
    /// about the app changes when the local `.storekit` file is swapped for
    /// real products — these strings are the whole contract.
    static let monthlyID = "com.giorgi.verbal.pro.monthly"
    static let yearlyID = "com.giorgi.verbal.pro.yearly"
    static let productIDs = [monthlyID, yearlyID]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoadingProducts = false
    #if DEBUG
    private var debugUnlocked = false
    #endif
    /// Why the last load failed, if it did.
    ///
    /// Kept because "no products" has several very different causes that look
    /// identical on screen — no StoreKit configuration attached to the launch,
    /// identifiers that don't match the configuration, or no network — and a
    /// swallowed error made all three the same shrug. Shown on the paywall in
    /// debug builds only.
    private(set) var loadError: String?

    /// Raised from anywhere, presented in exactly one place.
    ///
    /// `MainTabView` attaches the sheet; Home and the quote screen both need to
    /// raise it and both already own several sheets of their own, where a
    /// further one is silently ignored — the lesson recorded at the top of
    /// `MainTabView`'s own sheet.
    var isPaywallPresented = false

    /// Kept so the listener isn't collected. Never cancelled: this object lives
    /// as long as the app does, and a cancelled listener is a renewal missed.
    @ObservationIgnored private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task { await refreshEntitlement() }
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let found = try await Product.products(for: Self.productIDs)
            products = found
            // Succeeding and returning nothing is the common case when no
            // StoreKit configuration is attached to the launch: the request is
            // fine, the identifiers simply don't exist anywhere. Worth saying
            // plainly, because it looks the same as a failure and isn't one.
            loadError = found.isEmpty
                ? "StoreKit returned no products for \(Self.productIDs.joined(separator: ", ")). No configuration is attached to this launch, or the identifiers don't match it."
                : nil
        } catch {
            products = []
            loadError = error.localizedDescription
        }
    }

    /// Lets the paywall try again after a failure without relaunching.
    func reloadProducts() async {
        products = []
        loadError = nil
        await loadProducts()
    }

    /// Expired subscriptions are already absent from `currentEntitlements`; a
    /// refunded one is still listed but carries a revocation date, so both ends
    /// of "no longer paid for" have to be checked.
    func refreshEntitlement() async {
        var active = false
        // Collected alongside the boolean, and sent on. `isPro` is what this
        // screen believes; the server needs something it can check for itself,
        // and the signed blob is that. See `SubscriptionService`.
        var signed: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            active = true
            signed.append(result.jwsRepresentation)
        }
        #if DEBUG
        isPro = active || debugUnlocked
        #else
        isPro = active
        #endif

        // An empty list is a real answer and has to be sent: it is what a
        // cancellation looks like, and the server cannot tell "no longer
        // subscribed" from "the app went quiet" unless somebody says so.
        //
        // The debug unlock deliberately isn't reported. It exists so the
        // paywall can be stepped past on a simulator, and a switch in the app
        // that writes entitlement on the server is the exact thing the server
        // side of this was built not to have.
        await SubscriptionService.report(signedTransactions: signed)
    }

    #if DEBUG
    func unlockForDebug() {
        debugUnlocked = true
        isPro = true
    }
    #endif

    /// True when the purchase went through. A cancellation is not an error —
    /// the user deciding against it is an ordinary outcome, and only a genuine
    /// StoreKit failure is worth a message.
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        guard let userID = SupabaseManager.client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        // Apple carries this UUID forward into the signed transaction and its
        // renewals. The server verifies it before granting the subscription to
        // an account, so a genuine transaction cannot be copied to another
        // Verbal account.
        switch try await product.purchase(options: [.appAccountToken(userID)]) {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
            }
            await refreshEntitlement()
            return isPro
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    /// Whether another quote can be made.
    ///
    /// A nil remaining count means the server hasn't answered yet, and that is
    /// not the same as none left — `SessionStore` keeps the two apart on
    /// purpose. Nothing is refused on the strength of not knowing.
    func canCreateQuote(remaining: Int?) -> Bool {
        isPro || (remaining ?? .max) > 0
    }
}
