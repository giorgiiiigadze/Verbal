//
//  AboutView.swift
//  Verbal
//
//  The legal links and the build number. Off the main Settings list because
//  nobody arrives at Settings looking for a privacy policy — but App Review
//  does, and it has to be reachable in a predictable place.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                Link(destination: AppInfo.websiteURL) {
                    Label("Website", systemImage: "globe")
                }
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
            }
            .listRowBackground(Color(.cardSurface))

            Section {
                // Absent until the app is on the App Store. `requestReview` is
                // callable at any time but shows nothing before release and is
                // throttled after it, so as a row the user taps on purpose it
                // would do nothing on most taps — the worst kind of control.
                if let review = AppInfo.reviewURL {
                    Link(destination: review) {
                        Label("Rate Verbal", systemImage: "star")
                    }
                }
                LabeledContent("Version", value: AppInfo.versionLabel)
            } footer: {
                Text("Quote the version when you report something — it says exactly which build you're on.")
            }
            .listRowBackground(Color(.cardSurface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
