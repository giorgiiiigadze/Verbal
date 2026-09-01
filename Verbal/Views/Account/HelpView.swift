//
//  HelpView.swift
//  Verbal
//
//  Getting hold of a person. One door, deliberately — a help centre with two
//  rows and no articles behind them is a longer walk to the same email.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section {
                if let mail = AppInfo.supportMailURL {
                    Link(destination: mail) {
                        HStack(spacing: 8) {
                            Image(.contactSupport)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Contact support")
                        }
                    }
                } else {
                    // Should not happen — the address is a constant — but a
                    // dead-end screen is worse than a plain instruction.
                    LabeledContent("Email", value: AppInfo.supportEmail)
                }
            } header: {
                Text("Get in touch")
            } footer: {
                Text("Questions, bugs, or ideas. Your app and iOS versions are attached automatically, so nobody has to ask for them first.")
            }
            .listRowBackground(Color(.cardSurface))

            Section {
                Text("If a quote came out wrong, say what you said out loud and what it produced. That pairing is what makes a problem fixable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}
