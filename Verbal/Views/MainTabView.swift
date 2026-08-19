//
//  MainTabView.swift
//  Verbal
//

import SwiftUI
import UIKit

struct MainTabView: View {
    /// The rate card is deliberately absent: it lives in Home's header now.
    /// A tab is for somewhere you go back to; the rate card is something you
    /// set up, and it was holding a quarter of the bar for a monthly visit.
    private enum TabItem: Hashable { case home, clients, profile, record }

    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: TabItem = .home
    @State private var showCreate = false

    /// Announcements are shown once and never again. A promo that comes back is
    /// how people learn to dismiss your sheets without reading them.
    @AppStorage("seenShareLinkNews") private var seenShareLinkNews = false
    @State private var showShareLinkNews = false

    /// Unselected tabs are drawn in the same ink as the selected one, rather
    /// than the system's grey. Selection is still legible — iOS marks the
    /// current tab with a capsule behind it — so the colour was saying a second
    /// time what the shape already says, and greying three of four made the bar
    /// read as mostly disabled.
    ///
    /// Set on the appearance proxy because SwiftUI's `.tint` reaches only the
    /// selected item. Only this one property is touched: configuring a whole
    /// `UITabBarAppearance` would replace the bar's own background as well.
    init() {
        UITabBar.appearance().unselectedItemTintColor = UIColor(resource: .mainText)
    }

    /// Intercepts taps on the record "tab" before it ever becomes the selected
    /// tab. Letting it select and then snapping back in onChange briefly puts
    /// the search-role tab through its tab-bar morph, which corrupts the Home
    /// stack's navigation bar (broken title layout, lost push transitions,
    /// vanishing tab bar) after the sheet dismisses.
    private var tabSelection: Binding<TabItem> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .record {
                    showCreate = true
                } else {
                    selection = newValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            // Drawn rather than an SF Symbol, and stored as a template image so
            // it takes the TabView's tint like the symbols beside it — the
            // artwork's own red would otherwise sit in the bar ignoring both
            // selection and the colour scheme.
            Tab(value: TabItem.home) {
                HomeView(showCreate: $showCreate)
            } label: {
                Label {
                    Text("Home")
                } icon: {
                    Image(.homeTab)
                }
            }
            Tab("Clients", systemImage: "person.2.fill", value: .clients) {
                NavigationStack { ClientsView() }
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
            // instead of switching tabs. The mic glyph is force-tinted blue
            // (always-original) since this tab is never "selected", so the
            // TabView tint would otherwise leave it in the default color.
            //
            // Kept in the bar rather than promoted to a floating button of its
            // own: a button hovering over the list covers a row wherever it is
            // put, and the one it covers is always the newest quote.
            Tab(value: TabItem.record, role: .search) {
                Color.clear
            } label: {
                Label {
                    Text("Record")
                } icon: {
                    Image(uiImage: micIcon)
                }
            }
        }
        .tint(Color(.mainText))
        // Presented from here rather than Home: that view already owns several
        // sheets, and a further one attached to the same view is silently
        // ignored — a lesson the recording sheet learned the hard way.
        //
        // Only for someone who already has quotes. A first-run user never knew
        // sharing without a link, and telling them what changed before they've
        // sent anything is noise about an absence they never felt.
        .task(id: session.listsLoaded) {
            guard !seenShareLinkNews, session.listsLoaded, !session.quotes.isEmpty
            else { return }
            // After the tabs have settled: a sheet racing the first paint reads
            // as something that went wrong.
            try? await Task.sleep(for: .seconds(0.8))
            showShareLinkNews = true
        }
        .sheet(isPresented: $showShareLinkNews, onDismiss: { seenShareLinkNews = true }) {
            ShareLinkNewsSheet()
        }
    }

    /// The mic tab glyph, force-tinted with always-original rendering so it keeps
    /// its color regardless of selection state. Royal blue reads well on the light
    /// tab bar, but it's near-black on the dark one, so dark mode gets white.
    /// Computed (not a stored static) so it re-resolves when the scheme changes.
    ///
    /// Drawn a couple of points smaller than the bar's default and given a
    /// margin of its own. The mic sits in a separate container beside the tab
    /// pill, and at full size the glyph ran to the edge of that container, so
    /// the two touched and read as one run-on control. Insetting the artwork
    /// puts air between them without shrinking the button — the tap target is
    /// the container, not the image.
    private var micIcon: UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let base = UIImage(systemName: "mic.fill", withConfiguration: config) ?? UIImage()
        let tint: UIColor = colorScheme == .dark ? .white : UIColor(resource: .royalBlue600)
        return base
            .withTintColor(tint, renderingMode: .alwaysOriginal)
            .withAlignmentRectInsets(UIEdgeInsets(top: -4, left: -4, bottom: -4, right: -4))
    }

    /// The user's own face where there is one, and otherwise a filled person —
    /// the same weight as the filled pair next to it on the Clients tab. The
    /// outline version read as a different family of icon from its neighbours,
    /// and at tab-bar size an outlined circle with a head in it is a globe.
    @ViewBuilder
    private var profileIcon: some View {
        if let uiImage = session.avatarUIImage,
           let circular = Self.circularIcon(from: uiImage, size: 26) {
            Image(uiImage: circular)
        } else {
            Image(systemName: "person.crop.circle.fill")
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
