//
//  SettingsView.swift
//  Verbal
//

import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    LabeledContent("Name", value: session.profile?.fullName ?? "—")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { try? await session.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
