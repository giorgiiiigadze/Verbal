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

    /// Presents the native Google sheet and signs the user into Supabase.
    @MainActor
    static func signIn() async throws {
        guard let root = topViewController() else {
            throw GoogleAuthError.noPresenter
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleAuthError.missingIDToken
        }
        let accessToken = result.user.accessToken.tokenString

        try await SupabaseManager.client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
        )
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
