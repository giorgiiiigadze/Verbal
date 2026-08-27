//
//  GoogleAuth.swift
//  Verbal
//

import Foundation
import GoogleSignIn
import Supabase
import UIKit

enum GoogleAuthError: LocalizedError {
    case noPresenter
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .noPresenter: return "Couldn't find a screen to present Google Sign-In."
        case .missingIDToken: return "Google didn't return an ID token."
        }
    }
}

enum GoogleAuth {
    /// Configure the GoogleSignIn SDK. Call once at launch.
    static func configure() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: GoogleConfig.iosClientID
        )
    }

    /// True when the user backed out of Google's sheet. Not a failure — it is
    /// a decision, and reporting it as an error tells someone their deliberate
    /// action went wrong.
    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == kGIDSignInErrorDomain
            && error.code == GIDSignInError.canceled.rawValue
    }

    /// Presents the native Google sheet and signs the user into Supabase.
    ///
    /// `onAuthorized` fires once Google has finished and before the token is
    /// exchanged — the moment the waiting stops being the user's and starts
    /// being ours. Anything shown before that would be claiming to sign someone
    /// in while they are still choosing whether to.
    @MainActor
    static func signIn(onAuthorized: (() -> Void)? = nil) async throws {
        guard let root = topViewController() else {
            throw GoogleAuthError.noPresenter
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleAuthError.missingIDToken
        }
        let accessToken = result.user.accessToken.tokenString
        onAuthorized?()

        try await SupabaseManager.client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
        )
    }

    /// Clear Google's own local credentials as well as the Supabase session.
    /// Supabase and Google keep separate Keychain entries; signing out of only
    /// one leaves the other believing the account is still connected.
    @MainActor
    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    /// Revoke the Google grant after the app account has been deleted.
    ///
    /// Account deletion itself must not be held hostage by a second provider
    /// round trip after Supabase has already removed the account. If revocation
    /// cannot finish, at least remove Google's credentials from this device.
    @MainActor
    static func disconnectAfterAccountDeletion() async {
        guard GIDSignIn.sharedInstance.currentUser != nil else { return }
        do {
            try await GIDSignIn.sharedInstance.disconnect()
        } catch {
            GIDSignIn.sharedInstance.signOut()
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
