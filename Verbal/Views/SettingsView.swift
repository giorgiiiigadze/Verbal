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
            Section("Profile") {
                LabeledContent("Name", value: session.profile?.fullName ?? "—")
            }

            Section {
                NavigationLink {
                    BusinessProfileView()
                } label: {
                    Label("Business", systemImage: "briefcase")
                }
            } footer: {
                Text("Your business name, contact details, and quote defaults.")
            }

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

            Section {
                Button("Sign out", role: .destructive) {
                    Task { try? await session.signOut() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
