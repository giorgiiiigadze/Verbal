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
    /// The currency the user picked, held until they say what should happen to
    /// their saved rates.
    @State private var pendingCurrency: CurrencyTarget?

    /// Identifiable wrapper so a picked code can drive `.sheet(item:)`.
    private struct CurrencyTarget: Identifiable { let id: String }

    /// Saved rates that a currency switch would reinterpret.
    private var pricedRates: [RateCardItem] {
        session.rateCard.filter { $0.unitPrice != nil }
    }

    private var currency: Binding<AppCurrency> {
        Binding(
            get: { AppCurrency(rawValue: currencyCode) ?? .usd },
            set: { picked in
                guard picked.rawValue != currencyCode else { return }
                // A rate card stores bare numbers, so this setting is the only
                // thing saying whether 50 means $50 or £50. Switching it with
                // rates saved would redenominate all of them in silence, so ask
                // first. With nothing priced there is nothing to reinterpret.
                if pricedRates.isEmpty {
                    currencyCode = picked.rawValue
                } else {
                    pendingCurrency = CurrencyTarget(id: picked.rawValue)
                }
            }
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
                // Absent until the terms exist: a row that opens a 404 reads as
                // a broken app, and reviewers follow these links.
                if let terms = AppInfo.termsURL {
                    Link(destination: terms) {
                        Label("Terms of service", systemImage: "doc.text")
                    }
                }
                LabeledContent("Version", value: AppInfo.versionLabel)
            } header: {
                Text("About")
            }
            .listRowBackground(Color(.surface))

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
            .listRowBackground(Color(.surface))
        }
        // Nothing else is worth touching while the account is being removed.
        .disabled(isDeleting)
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
        .sheet(item: $pendingCurrency) { target in
            ConvertRateCardSheet(items: pricedRates,
                                 fromCode: currencyCode,
                                 toCode: target.id) { converted in
                currencyCode = target.id
                if converted {
                    Task { await session.refreshRateCard() }
                    toast = Toast(style: .success, message: "Rates converted to \(target.id)")
                }
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
