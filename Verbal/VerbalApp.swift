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

    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.system.rawValue

    private var preferredColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearance) ?? .system).colorScheme
    }

    init() {
        GoogleAuth.configure()
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
                .preferredColorScheme(preferredColorScheme)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
