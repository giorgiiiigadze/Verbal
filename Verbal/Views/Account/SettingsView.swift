//
//  SettingsView.swift
//  Verbal
//

import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    @State private var showSignOutConfirmation = false
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
            .listRowBackground(Color(.cardSurface))

            // Three doors rather than three more sections. Support, legal and
            // deletion were all laid out here in full, which put "Delete
            // account" one flick from the currency picker and made a screen with
            // two real settings on it look like a screen with nine.
            Section {
                NavigationLink {
                    HelpView()
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                NavigationLink {
                    OtherView()
                } label: {
                    Label("Other", systemImage: "ellipsis.circle")
                }
            }
            .listRowBackground(Color(.cardSurface))

            // Signing out stays in the open: it is routine, reversible, and the
            // thing people actually come here to do. Deleting the account is
            // none of those, and lives behind "Other".
            Section {
                Button("Sign out", role: .destructive) {
                    showSignOutConfirmation = true
                }
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out of Verbal?", isPresented: $showSignOutConfirmation) {
            Button("Sign out", role: .destructive) {
                Task { try? await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your quotes stay safe — you'll just need to sign in again.")
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
}
