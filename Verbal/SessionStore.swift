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

    /// The user's avatar, downloaded and decoded during bootstrap so it shows
    /// instantly (no visible load) once the splash screen dismisses.
    private(set) var avatarImage: Image?

    /// True once the initial data needed for first paint has finished loading.
    /// The splash screen stays up until this is true.
    private(set) var isBootstrapped = false

    private let client = SupabaseManager.client

    /// Resolve the initial state and preload first-paint data, then keep
    /// listening for auth changes.
    func start() async {
        if let session = client.auth.currentSession, !session.isExpired {
            await bootstrap()
            state = .ready
        } else {
            state = .signedOut
        }
        isBootstrapped = true

        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .userUpdated, .tokenRefreshed:
                if let session = change.session, !session.isExpired {
                    await bootstrap()
                    state = .ready
                } else {
                    clearSession()
                }
            case .signedOut:
                clearSession()
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
    }

    private func clearSession() {
        profile = nil
        avatarImage = nil
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
            }
        } catch {
            // Fall back to the placeholder icon if the download fails.
        }
    }

    // MARK: - Auth actions

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
