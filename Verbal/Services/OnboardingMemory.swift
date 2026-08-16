//
//  OnboardingMemory.swift
//  Verbal
//
//  Remembers that this person has been through onboarding, across a delete and
//  reinstall.
//
//  In the Keychain rather than UserDefaults, which is the whole point: deleting
//  an app wipes its defaults but leaves its Keychain items, so a returning user
//  who signed out before deleting used to be met by the pitch and asked their
//  trade again — the one person you least want to greet as a stranger, since
//  they already left once.
//
//  The auth session is kept the same way, by the Supabase client, which is why
//  someone who reinstalls without signing out lands straight in their quotes.
//  This puts the onboarding flag on the same footing.
//

import Foundation
import Security

enum OnboardingMemory {
    private static let account = "hasSeenOnboarding"
    private static let service = "app.verbal.onboarding"

    /// True once this person has seen onboarding on this device, whatever has
    /// happened to the app since.
    static var hasSeenOnboarding: Bool {
        get { read() }
        set { newValue ? write() : erase() }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess { return true }

        // Everyone who onboarded before this moved to the Keychain has the
        // answer in their defaults instead. Without this, updating the app
        // while signed out would show them the pitch again — the exact thing
        // the Keychain is here to prevent, done to the people who have been
        // using it longest.
        //
        // Promoted rather than just read, so the defaults copy stops mattering
        // from the first launch after the update.
        if UserDefaults.standard.bool(forKey: legacyDefaultsKey) {
            write()
            return true
        }
        return false
    }

    /// Where this lived before the Keychain. Left in place rather than removed:
    /// it costs nothing, and reading it is the only way to recognise a user who
    /// updates while signed out.
    private static let legacyDefaultsKey = "hasSeenOnboarding"

    private static func write() {
        guard !read() else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data([1])
        // This device only, and only while it is unlocked. Nothing here is
        // worth syncing to another phone — a second device is a first run on
        // that device — and nothing needs reading before the user has unlocked.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Forget them. Called when an account is deleted, and useful for wiping
    /// the slate in development. Signing out must NOT call this: leaving is
    /// not forgetting, and the next launch should offer sign-in rather than
    /// the pitch.
    static func erase() {
        SecItemDelete(baseQuery as CFDictionary)
        // The old key too, or the migration in `read()` promotes it straight
        // back and this device can never be forgotten.
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }
}
