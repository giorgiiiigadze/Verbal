//
//  VerbalApp.swift
//  Verbal
//
//  Created by giorgi giorgadze on 26/07/2026.
//

import SwiftUI
import GoogleSignIn

@main
struct VerbalApp: App {
    init() {
        GoogleAuth.configure()
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
