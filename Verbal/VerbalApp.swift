//
//  VerbalApp.swift
//  Verbal
//
//  Created by giorgi giorgadze on 26/07/2026.
//

import SwiftUI
import UIKit
import GoogleSignIn
import UserNotifications

@main
struct VerbalApp: App {
    private static let notificationDelegate = AppNotificationDelegate()

    init() {
        GoogleAuth.configure()
        RevenueCatService.configure()
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
        configureNavigationTitleWeight()
    }

    /// Use Roboto Slab for navigation titles (the app's primary font).
    private func configureNavigationTitleWeight() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        let largeTitleFont = UIFont(name: "RobotoSlab-Regular", size: 34)
            ?? .systemFont(ofSize: 34, weight: .regular)
        let inlineTitleFont = UIFont(name: "RobotoSlab-Regular", size: 17)
            ?? .systemFont(ofSize: 17, weight: .semibold)
        appearance.largeTitleTextAttributes = [.font: largeTitleFont]
        appearance.titleTextAttributes = [.font: inlineTitleFont]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppNotificationRouter.shared)
                .onOpenURL { url in
                    if url.scheme == "verbal" {
                        AppNotificationRouter.shared.handleDeepLink(url)
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
        }
    }
}
