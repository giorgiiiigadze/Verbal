//
//  RevenueCatService.swift
//  Verbal
//
//  A deliberately narrow bridge while StoreKit remains the purchase and
//  entitlement authority. Supplying no public key leaves RevenueCat disabled.
//

import Foundation
import RevenueCat

@MainActor
enum RevenueCatService {
    static let entitlementID = "pro"
    static let apiKeyInfoPlistKey = "RevenueCatAPIKey"

    private(set) static var isConfigured = false
    private static var identifiedUserID: UUID?

    /// Configure once at launch as an anonymous customer. Verbal still calls
    /// StoreKit 2 and finishes its own transactions, so RevenueCat must only
    /// observe purchases until the eventual full migration is deliberate.
    static func configure(bundle: Bundle = .main) {
        guard !isConfigured,
              let key = configuredAPIKey(in: bundle)
        else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: key)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build()
        )
        isConfigured = true
    }

    /// RevenueCat customer IDs use the same stable UUID as Supabase. This
    /// avoids anonymous purchases becoming detached from the signed-in account.
    static func identify(_ userID: UUID) async {
        guard isConfigured, identifiedUserID != userID else { return }
        do {
            _ = try await Purchases.shared.logIn(userID.uuidString)
            identifiedUserID = userID
            // Observer mode does not automatically import purchases made
            // before configuration, so sync after the first identified login.
            _ = try await Purchases.shared.syncPurchases()
        } catch {
            // Analytics must never block auth or revoke StoreKit entitlement.
            #if DEBUG
            print("RevenueCat identity sync failed: \(error.localizedDescription)")
            #endif
        }
    }

    static func resetIdentity() async {
        guard isConfigured, identifiedUserID != nil else { return }
        do {
            _ = try await Purchases.shared.logOut()
            identifiedUserID = nil
        } catch {
            #if DEBUG
            print("RevenueCat logout failed: \(error.localizedDescription)")
            #endif
        }
    }

    static func configuredAPIKey(in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: apiKeyInfoPlistKey) as? String else {
            return nil
        }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("$(") else { return nil }
        return key
    }
}
