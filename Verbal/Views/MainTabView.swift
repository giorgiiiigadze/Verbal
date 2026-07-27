//
//  MainTabView.swift
//  Verbal
//

import SwiftUI
import UIKit

struct MainTabView: View {
    private enum TabItem: Hashable { case home, rateCard, profile, record }

    @Environment(SessionStore.self) private var session
    @State private var selection: TabItem = .home
    @State private var showCreate = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(showCreate: $showCreate)
            }
            Tab("Rate card", systemImage: "list.bullet.rectangle", value: .rateCard) {
                NavigationStack { RateCardView() }
            }
            Tab(value: TabItem.profile) {
                NavigationStack { ProfileView() }
            } label: {
                Label {
                    Text("Profile")
                } icon: {
                    profileIcon
                }
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

    @ViewBuilder
    private var profileIcon: some View {
        if let uiImage = session.avatarUIImage,
           let circular = Self.circularIcon(from: uiImage, size: 26) {
            Image(uiImage: circular)
        } else {
            Image(systemName: "person.crop.circle")
        }
    }

    /// Renders a source image into a small circular, original-rendering tab-bar icon.
    private static func circularIcon(from image: UIImage, size: CGFloat) -> UIImage? {
        let target = CGSize(width: size, height: size)
        let format = UIGraphicsImageRendererFormat.default()
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let output = renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: target)).addClip()
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let w = image.size.width * scale
            let h = image.size.height * scale
            image.draw(in: CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h))
        }
        return output.withRenderingMode(.alwaysOriginal)
    }
}
