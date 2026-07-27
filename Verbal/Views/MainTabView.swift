//
//  MainTabView.swift
//  Verbal
//

import SwiftUI

struct MainTabView: View {
    private enum TabItem: Hashable { case home, settings, record }

    @State private var selection: TabItem = .home
    @State private var showCreate = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(showCreate: $showCreate)
            }
            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
            // Detached trailing button in the tab bar — opens the recording sheet
            // instead of switching tabs.
            Tab("Record", systemImage: "mic.fill", value: .record, role: .search) {
                Color.clear
            }
        }
        .tint(Color(.mainText))
        .onChange(of: selection) { _, newValue in
            if newValue == .record {
                selection = .home
                showCreate = true
            }
        }
    }
}
