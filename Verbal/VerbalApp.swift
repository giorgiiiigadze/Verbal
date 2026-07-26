//
//  VerbalApp.swift
//  Verbal
//
//  Created by giorgi giorgadze on 26/07/2026.
//

import SwiftUI
import UIKit
import GoogleSignIn

@main
struct VerbalApp: App {
    init() {
        GoogleAuth.configure()
        configureNavigationTitleWeight()
    }

    /// Lighten the (otherwise bold) navigation titles to semibold.
    private func configureNavigationTitleWeight() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .regular)
        ]
        appearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
