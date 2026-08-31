//
//  SubscriptionService.swift
//  Verbal
//
//  Telling the server what StoreKit says, in a form the server can check.
//
//  The app knows whether it is entitled — `Transaction.currentEntitlements` is
//  the authority and always will be for what the screen shows. The database
//  cannot take the app's word for it, though: the publishable key ships inside
//  the binary, and anything holding it can claim whatever it likes. So what
//  gets sent is not a boolean. It is the transaction's `jwsRepresentation` —
//  the blob Apple signed, carrying a certificate chain up to Apple's own root —
//  and `verify-subscription` checks that signature before writing anything.
//
//  A patched client can send anything here. The worst it can do is fail
//  verification, because a signature is not something it can forge.
//

import Foundation
import StoreKit
import Supabase

enum SubscriptionService {
    private static var client: SupabaseClient { SupabaseManager.client }

    /// The last payload we successfully reported, so an unchanged entitlement
    /// isn't re-sent on every `Transaction.updates` tick — which fires on
    /// renewals, refunds, and app launches alike.
    ///
    /// Deliberately in memory rather than on disk: it is a de-duplication
    /// convenience, and starting each launch by reporting once is exactly the
    /// behaviour worth keeping. A stale entitlement on the server expires by
    /// itself; a missing one that nothing ever re-reports would not.
    @MainActor private static var lastReported: [String]?

    /// Push the current entitlement to the server.
    ///
    /// Silent on failure and non-blocking by design. It is a background fact,
    /// not something the user asked for, and an offline phone cannot do
    /// anything about it — the stored expiry keeps a subscriber past the
    /// paywall until it lapses on its own, so a missed report costs nothing
    /// until it has been missed for a very long time.
    @MainActor
    static func report(signedTransactions: [String], force: Bool = false) async {
        guard client.auth.currentUser != nil else { return }
        guard force || lastReported != signedTransactions else { return }

        struct Payload: Encodable {
            let signed_transactions: [String]
        }
        do {
            try await client.functions.invoke(
                "verify-subscription",
                options: FunctionInvokeOptions(body: Payload(signed_transactions: signedTransactions))
            )
            lastReported = signedTransactions
        } catch {
            // Left unreported, so the next refresh tries again.
        }
    }

    /// Forget what was reported, so the next refresh speaks up.
    ///
    /// Signing out doesn't change what this device is entitled to, but it does
    /// change whose profile the answer belongs on: without this, signing into a
    /// second account on the same phone would find the entitlement "already
    /// reported" and never tell the server about it.
    @MainActor
    static func forgetLastReport() {
        lastReported = nil
    }
}
