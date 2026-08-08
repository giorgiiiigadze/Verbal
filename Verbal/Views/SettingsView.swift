//
//  SettingsView.swift
//  Verbal
//

import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

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
            // Currency belongs here rather than in a section of its own: it is
            // a quote-formatting setting, and one row wrapped in its own header
            // and footer is more chrome than content on a screen this short.
            Section {
                NavigationLink {
                    QuoteDefaultsView()
                } label: {
                    Label("Quote defaults", systemImage: "doc.plaintext")
                }
                Picker("Main currency", selection: currency) {
                    ForEach(AppCurrency.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Quotes")
            } footer: {
                // Names the letterhead: it is the most visible thing behind
                // that row and this description was written before it moved
                // there, so it was pointing at a screen it no longer described.
                Text("Your letterhead, validity, tax and standard terms, applied to every new quote. The currency also formats your rate card.")
            }
            .listRowBackground(Color(.surface))

            Section {
                if let mail = AppInfo.supportMailURL {
                    Link(destination: mail) {
                        Label("Contact support", systemImage: "envelope")
                    }
                }
                // Absent until the app is on the App Store. `requestReview` is
                // callable at any time but shows nothing before release and is
                // throttled after it, so as a row the user taps on purpose it
                // would do nothing on most taps — the worst kind of control.
                if let review = AppInfo.reviewURL {
                    Link(destination: review) {
                        Label("Rate Verbal", systemImage: "star")
                    }
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
