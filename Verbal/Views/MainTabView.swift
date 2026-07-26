//
//  MainTabView.swift
//  Verbal
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView()
            }
            // `.search` role renders this tab detached, alone on the trailing side.
            Tab("Create", systemImage: "plus", role: .search) {
                CreateView()
            }
        }
        .tint(Color(.mainText))
    }
}
