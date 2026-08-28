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
    private enum TabItem: Hashable { case home, schedule, clients, account }

    @Environment(SessionStore.self) private var session
    @Environment(Store.self) private var store
    @Environment(AppNotificationRouter.self) private var notificationRouter
    @State private var selection: TabItem = .home
    @State private var showCreate = false
    @State private var recordingVisit: ScheduledVisit?
    @State private var savedRecordingQuoteID: UUID?
    /// Set when the recorder's save was refused for want of allowance. Acted on
    /// in `onDismiss` below rather than when it happens: the paywall and the
    /// recorder are both sheets on this view, and raising the second while the
    /// first is still going is how a sheet gets silently swallowed.
    @State private var recordingHitPaywall = false

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
        TabView(selection: $selection) {
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
            // Home keeps the compact Upcoming card for the next few jobs. This
            // is the full working view of the diary: somewhere worth returning
            // to throughout the day, and therefore worth a permanent tab.
            Tab("Visits", systemImage: "calendar", value: .schedule) {
                NavigationStack {
                    ScheduleView(showCreate: createBinding,
                                 recordingVisit: $recordingVisit)
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
            // Now that the recorder is actually gone, the paywall has the
            // screen to itself.
            if recordingHitPaywall {
                recordingHitPaywall = false
                store.isPaywallPresented = true
            }
        }) {
            QuoteRecordingView(
                scheduledVisit: recordingVisit,
                onSavedQuote: { quoteId in
                    // The recorder can be started from either Home or Visits.
                    // Keep the association here, at their shared owner, so a
                    // completed quote is never dependent on Home being alive or
                    // up to date.
                    if let visit = recordingVisit {
                        session.visitStore.markRecorded(visit, quoteId: quoteId)
                        ScheduledVisitNotifications.cancel(visit)
                    }
                    savedRecordingQuoteID = quoteId
                },
                onAllowanceExhausted: { recordingHitPaywall = true }
            )
            .environment(session)
            .environment(store)
        }
        .onChange(of: notificationRouter.requestedQuoteId) { _, quoteId in
            guard quoteId != nil else { return }
            selection = .home
        }
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
    /// Keeping this avoids replacing the tab item's image every time the
    /// recording sheet opens or closes.
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
