//
//  SettingsView.swift
//  Verbal
//

import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

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
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
