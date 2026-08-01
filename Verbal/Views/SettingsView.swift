//
//  SettingsView.swift
//  Verbal
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    /// The system review prompt — Apple limits how often it actually appears,
    /// so this is a request rather than a guarantee.
    @Environment(\.requestReview) private var requestReview

    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    @State private var showDeleteSheet = false
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
                if let mail = AppInfo.supportMailURL {
                    Link(destination: mail) {
                        Label("Contact support", systemImage: "envelope")
                    }
                }
                Button {
                    requestReview()
                } label: {
                    Label("Rate Verbal", systemImage: "star")
                }
            } header: {
                Text("Support")
            } footer: {
                Text("Questions, bugs, or ideas — the email arrives with your app version attached.")
            }
            .listRowBackground(Color(.surface))

            Section {
                Link(destination: AppInfo.privacyPolicyURL) {
                    Label("Privacy policy", systemImage: "hand.raised")
                }
                Link(destination: AppInfo.termsURL) {
                    Label("Terms of service", systemImage: "doc.text")
                }
                LabeledContent("Version", value: AppInfo.versionLabel)
            } header: {
                Text("About")
            }
            .listRowBackground(Color(.surface))

            Section {
                Button("Delete account", role: .destructive) {
                    showDeleteSheet = true
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
}
