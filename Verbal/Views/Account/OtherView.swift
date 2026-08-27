//
//  OtherView.swift
//  Verbal
//
//  Where account deletion lives. Buried on purpose: it sat on the main Settings
//  list one tap from everything routine, and the only person who should reach it
//  is one who went looking.
//

import SwiftUI

struct OtherView: View {
    @Environment(SessionStore.self) private var session

    @State private var showDeleteSheet = false
    @State private var isDeleting = false
    @State private var toast: Toast?

    var body: some View {
        List {
#if DEBUG
            Section {
                Button {
                    showOnboardingAgain()
                } label: {
                    Label("Show onboarding again", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("Debug only. Clears the local onboarding flag and signs out so the next screen is the first-run flow.")
            }
            .listRowBackground(Color(.cardSurface))
#endif

            Section {
                // Deletion is a round trip to the edge function followed by a
                // sign-out. Left as a merely disabled button it reads as a tap
                // that did nothing, on the one action nobody should have to
                // wonder about.
                if isDeleting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Deleting account…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Delete account", role: .destructive) {
                        showDeleteSheet = true
                    }
                }
            } footer: {
                Text("Permanently removes your account, quotes, and rate card. This can't be undone.")
            }
            .listRowBackground(Color(.cardSurface))
        }
        // Nothing else is worth touching while the account is being removed.
        .disabled(isDeleting)
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Other")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDeleteSheet) {
            DeleteAccountSheet { reason in
                showDeleteSheet = false
                deleteAccount(reason: reason)
            }
        }
        .toast($toast)
    }

    /// On success the session signs out, which returns the app to the auth
    /// screen — so there's no success state to show here.
    private func deleteAccount(reason: String) {
        isDeleting = true
        Task {
            // Feedback first: once the account is gone the session can't write.
            await session.recordDeletionFeedback(reason: reason)
            do {
                try await session.deleteAccount()
            } catch {
                isDeleting = false
                toast = Toast(style: .error, message: "Couldn't delete account")
            }
        }
    }

#if DEBUG
    private func showOnboardingAgain() {
        OnboardingMemory.erase()
        OnboardingDraft.clear()
        UserDefaults.standard.removeObject(forKey: "pendingTrade")
        Task { await session.signOut() }
    }
#endif
}
