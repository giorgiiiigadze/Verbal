//
//  SessionStore.swift
//  Verbal
//

import Foundation
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

    private let client = SupabaseManager.client

    /// Start listening to auth changes and resolve the initial state.
    func start() async {
        // Resolve the initial state immediately from locally stored session,
        // so the UI never sits on a blank loading screen waiting on the network.
        if let session = client.auth.currentSession, !session.isExpired {
            state = .ready
            await refreshProfile()
        } else {
            state = .signedOut
        }

        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .userUpdated, .tokenRefreshed:
                if let session = change.session, !session.isExpired {
                    state = .ready
                    await refreshProfile()
                } else {
                    state = .signedOut
                }
            case .signedOut:
                profile = nil
                state = .signedOut
            default:
                break
            }
        }
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

    // MARK: - Auth actions

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
