//
//  SettingsView.swift
//  Verbal
//

import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var toast: Toast?

    private var currency: Binding<AppCurrency> {
        Binding(
            get: { AppCurrency(rawValue: currencyCode) ?? .usd },
            set: { currencyCode = $0.rawValue }
        )
    }

    var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountView()
                } label: {
                    HStack(spacing: 14) {
                        AvatarView(image: session.avatarImage,
                                   urlString: session.profile?.avatarUrl, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.profile?.fullName ?? "—")
                                .font(.headline)
                                .foregroundStyle(Color(.mainText))
                            if let email = session.email, !email.isEmpty {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .listRowBackground(Color(.surface))

            Section {
                NavigationLink {
                    QuoteDefaultsView()
                } label: {
                    Label("Quote defaults", systemImage: "doc.plaintext")
                }
            } header: {
                Text("Quotes")
            } footer: {
                Text("Validity, terms, and notes pre-filled on every new quote.")
            }
            .listRowBackground(Color(.surface))

            Section {
                Picker("Main currency", selection: currency) {
                    ForEach(AppCurrency.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Currency")
            } footer: {
                Text("Used to format totals in your quotes and rate card.")
            }
            .listRowBackground(Color(.surface))

            Section {
                Button("Sign out", role: .destructive) {
                    Task { try? await session.signOut() }
                }
            }
            .listRowBackground(Color(.surface))

            Section {
                Button("Delete account", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(isDeleting)
            } footer: {
                Text("Permanently removes your account, quotes, and rate card. This can't be undone.")
            }
            .listRowBackground(Color(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $showDeleteConfirmation) {
            Button("Delete account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and every quote, rate, and business detail saved to it. This can't be undone.")
        }
        .toast($toast)
    }

    /// On success the session signs out, which returns the app to the auth
    /// screen — so there's no success state to show here.
    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                try await session.deleteAccount()
            } catch {
                isDeleting = false
                toast = Toast(style: .error, message: "Couldn't delete account")
            }
        }
    }
}
