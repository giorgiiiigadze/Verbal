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
    ///
    /// Account is the same argument run the other way. Profile and Settings
    /// were one tab and a gear in its corner, which buried the settings people
    /// go looking for behind a form they fill in once. One tab now holds both.
    private enum TabItem: Hashable { case home, clients, account, record }

    @Environment(SessionStore.self) private var session
    @Environment(Store.self) private var store
    @Environment(AppNotificationRouter.self) private var notificationRouter
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: TabItem = .home
    @State private var showCreate = false
    @State private var recordingVisit: ScheduledVisit?
    @State private var savedRecordingQuoteID: UUID?

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

    /// How long the tab bar is given to finish changing its mind about the
    /// record "tab" before the recorder is asked for. Long enough for UIKit to
    /// put its selection back where it found it; short enough that the mic
    /// still answers on the tap.
    private static let tabBarSettleDelay = Duration.milliseconds(150)

    /// Intercepts taps on the record "tab" before it ever becomes the selected
    /// tab — and then waits a beat before opening anything.
    ///
    /// Refusing the value here is only half of it. This setter runs from inside
    /// the tab bar's own selection callback, and by the time it runs UIKit has
    /// already moved its tab bar controller onto the record tab and has to move
    /// back off it. Raising a sheet in that same turn covers the controller
    /// mid-move: the modal suspends the child appearance callbacks, so Home's
    /// navigation controller is left having been told it was going away and
    /// never told it came back.
    ///
    /// A navigation controller in that state believes it is off screen, and
    /// UIKit treats it accordingly — it pushes without animating and it doesn't
    /// lay its bar out, so the pushed screen is handed no room at the top. That
    /// is the quote screen appearing instantly with its title jammed under the
    /// status bar, and it lasts until something else brings the stack back.
    ///
    /// Handing the presentation to a later turn lets the tab bar finish
    /// reverting first, so the sheet goes up over a settled controller.
    private var tabSelection: Binding<TabItem> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .record {
                    Task {
                        try? await Task.sleep(for: Self.tabBarSettleDelay)
                        requestCreate()
                    }
                } else {
                    selection = newValue
                }
            }
        )
    }

    /// The one gate on making a new quote.
    ///
    /// `showCreate` is state of this view, and Home only ever sets it through
    /// the binding below, so every way into the recorder — the mic in the bar,
    /// a scheduled visit, both empty states — arrives here. One check rather
    /// than five copies of one, and no way to add a sixth entry point that
    /// quietly skips it.
    private func requestCreate() {
        if store.canCreateQuote(remaining: session.freeQuotesRemaining) {
            recordingVisit = nil
            showCreate = true
        } else {
            store.isPaywallPresented = true
        }
    }

    /// What Home is handed in place of `$showCreate`. Setting it true asks;
    /// setting it false — which is what the sheet's own dismissal does — closes
    /// without asking anything.
    private var createBinding: Binding<Bool> {
        Binding(
            get: { showCreate },
            set: { wantsToCreate in
                if wantsToCreate {
                    if store.canCreateQuote(remaining: session.freeQuotesRemaining) {
                        showCreate = true
                    } else {
                        store.isPaywallPresented = true
                    }
                } else {
                    showCreate = false
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
                HomeView(showCreate: createBinding,
                         recordingVisit: $recordingVisit,
                         savedRecordingQuoteID: $savedRecordingQuoteID)
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
            Tab(value: TabItem.account) {
                NavigationStack { AccountView() }
            } label: {
                Label {
                    Text("Account")
                } icon: {
                    accountIcon
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
        // The app's only paywall presentation, for the same reason the sheet
        // above lives here: Home and the quote screen both need to raise it and
        // both already own several sheets, where a further one is ignored.
        .sheet(isPresented: Bindable(store).isPaywallPresented) {
            PaywallSheet(remaining: session.freeQuotesRemaining)
        }
        .sheet(isPresented: $showCreate, onDismiss: {
            recordingVisit = nil
        }) {
            QuoteRecordingView(scheduledVisit: recordingVisit) { quoteId in
                savedRecordingQuoteID = quoteId
            }
            .environment(session)
        }
        .onChange(of: notificationRouter.requestedQuoteId) { _, quoteId in
            guard quoteId != nil else { return }
            selection = .home
        }
    }

    /// The mic tab glyph, force-tinted with always-original rendering so it keeps
    /// its color regardless of selection state. Royal blue reads well on the light
    /// tab bar, but it's near-black on the dark one, so dark mode gets white:
    /// hence one glyph per scheme, picked by `micIcon` below.
    ///
    /// Drawn a couple of points smaller than the bar's default and given a
    /// margin of its own. The mic sits in a separate container beside the tab
    /// pill, and at full size the glyph ran to the edge of that container, so
    /// the two touched and read as one run-on control. Insetting the artwork
    /// puts air between them without shrinking the button — the tap target is
    /// the container, not the image.
    ///
    /// Both are built once and kept. This body runs again every time the
    /// recorder opens or closes, and rendering a fresh `UIImage` each time
    /// handed the tab bar a new item image to lay out — churn in the bar during
    /// exactly the transition this screen is trying to hold still.
    private static let lightMicIcon = MainTabView.makeMicIcon(tint: UIColor(resource: .royalBlue600))
    private static let darkMicIcon = MainTabView.makeMicIcon(tint: .white)

    private static func makeMicIcon(tint: UIColor) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let base = UIImage(systemName: "mic.fill", withConfiguration: config) ?? UIImage()
        return base
            .withTintColor(tint, renderingMode: .alwaysOriginal)
            .withAlignmentRectInsets(UIEdgeInsets(top: -4, left: -4, bottom: -4, right: -4))
    }

    private var micIcon: UIImage {
        colorScheme == .dark ? Self.darkMicIcon : Self.lightMicIcon
    }

    /// The user's own face where there is one, and otherwise a filled person —
    /// the same weight as the filled pair next to it on the Clients tab. The
    /// outline version read as a different family of icon from its neighbours,
    /// and at tab-bar size an outlined circle with a head in it is a globe.
    @ViewBuilder
    private var accountIcon: some View {
        if let uiImage = session.avatarUIImage,
           let circular = Self.avatarIcon(for: uiImage) {
            Image(uiImage: circular)
        } else {
            Image(systemName: "person.crop.circle.fill")
        }
    }

    /// The last avatar that was cropped, and what it was cropped to.
    ///
    /// Same reason the mic glyphs above are held: without this, every run of
    /// `body` — and the recorder alone causes two — put a fresh
    /// `UIGraphicsImageRenderer` pass through the tab bar's account item.
    private static var lastAvatarSource: UIImage?
    private static var lastAvatarIcon: UIImage?

    private static func avatarIcon(for image: UIImage) -> UIImage? {
        if lastAvatarSource === image { return lastAvatarIcon }
        let icon = MainTabView.circularIcon(from: image, size: 26)
        lastAvatarSource = image
        lastAvatarIcon = icon
        return icon
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
