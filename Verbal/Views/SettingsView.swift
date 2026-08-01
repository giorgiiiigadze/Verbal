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
                Button("Sign out", role: .destructive) {
                    Task { try? await session.signOut() }
                }
            }
            .listRowBackground(Color(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
