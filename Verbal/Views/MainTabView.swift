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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: TabItem = .home
    @State private var showCreate = false
    /// The database owns the allowance. Refresh it before opening the recorder
    /// so a stale in-memory count cannot let somebody record and generate a
    /// quote that the server will refuse only when they tap Done.
    @State private var isCheckingQuoteAllowance = false
    @State private var allowanceCheckFailed = false
    @State private var recordingVisit: ScheduledVisit?
    @State private var savedRecordingQuoteID: UUID?
    /// Set when the recorder's save was refused for want of allowance. Acted on
    /// in `onDismiss` below rather than when it happens: the paywall and the
    /// recorder are both sheets on this view, and raising the second while the
    /// first is still going is how a sheet gets silently swallowed.
    @State private var recordingHitPaywall = false
    @AppStorage("hasSeenRecordingIntro") private var hasSeenRecordingIntro = false
    @State private var showRecordingIntro = false
    @State private var startRecordingAfterIntro = false
    /// Calendar is introduced where it is useful: when someone first chooses
    /// the tab, rather than adding another sheet to the end of sign-in.
    @State private var showCalendarIntro = false
    @State private var startBookingAfterCalendarIntro = false
    @State private var calendarBookingRequest = false
    @State private var calendarVisitRequestID: UUID?

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
                    // The other half of the race above: the announcement can be
                    // raised in the same tick as this tap, and then neither is
                    // guarded by the other. Losing one tap while a sheet is
                    // arriving costs a second tap; losing the race costs the
                    // record button until the app is relaunched.
                    guard !showShareLinkNews else { return }
                    Task { await requestCreate() }
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
                         savedRecordingQuoteID: $savedRecordingQuoteID,
                         onShowCalendar: { selection = .schedule })
            } label: {
                Label {
                    Text("Home")
                } icon: {
                    Image(.homeTab)
                }
            }
            // Home keeps a compact, scrollable Upcoming card. This is the full
            // working view of the diary: somewhere worth returning to
            // throughout the day, and therefore worth a permanent tab.
            Tab("Calendar", systemImage: "calendar", value: .schedule) {
                NavigationStack {
                    ScheduleView(showCreate: createBinding,
                                 recordingVisit: $recordingVisit,
                                 startBooking: $calendarBookingRequest,
                                 requestedVisitID: $calendarVisitRequestID)
                }
            }
            .badge(notificationRouter.hasUnreadVisitReminder ? Text("1") : nil)
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
        .eraseToAnyView()
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
            presentShareLinkNewsIfNeeded()
        }
        .task { await notificationRouter.refreshVisitReminderBadge() }
        .sheet(isPresented: $showShareLinkNews, onDismiss: { seenShareLinkNews = true }) {
            ShareLinkNewsSheet()
        }
        // The app's only paywall presentation, for the same reason the sheet
        // above lives here: Home and the quote screen both need to raise it and
        // both already own several sheets, where a further one is ignored.
        .sheet(isPresented: Bindable(store).isPaywallPresented) {
            PaywallSheet(remaining: session.freeQuotesRemaining)
        }
        .alert("Couldn't check your quote allowance", isPresented: $allowanceCheckFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try recording again.")
        }
        .sheet(isPresented: $showRecordingIntro, onDismiss: {
            hasSeenRecordingIntro = true
            guard startRecordingAfterIntro else { return }
            startRecordingAfterIntro = false
            showCreate = true
        }) {
            RecordingIntroSheet {
                startRecordingAfterIntro = true
                showRecordingIntro = false
            }
        }
        .sheet(isPresented: $showCalendarIntro, onDismiss: {
            markCalendarIntroSeen()
            guard startBookingAfterCalendarIntro else { return }
            startBookingAfterCalendarIntro = false
            calendarBookingRequest = true
        }) {
            CalendarIntroSheet {
                startBookingAfterCalendarIntro = true
                showCalendarIntro = false
            }
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
        .onChange(of: notificationRouter.requestedVisitId) { _, visitId in
            guard let visitId else { return }
            calendarVisitRequestID = visitId
            selection = .schedule
            notificationRouter.clearVisitReminder()
            notificationRouter.requestedVisitId = nil
        }
        .onChange(of: selection) { _, selectedTab in handleTabSelection(selectedTab) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await notificationRouter.refreshVisitReminderBadge() }
        }
        .onChange(of: session.visitStore.hasCompletedInitialSync) { _, _ in
            presentCalendarIntroIfNeeded()
        }
    }

    /// Reconcile the cached count with the server at the moment it matters.
    /// The insert trigger remains the final authority for races across devices,
    /// but an ordinary exhausted account now sees the paywall before recording.
    @MainActor
    private func requestCreate() async {
        guard !isCheckingQuoteAllowance else { return }
        isCheckingQuoteAllowance = true
        defer { isCheckingQuoteAllowance = false }

        guard await session.refreshQuoteUsage() != nil else {
            allowanceCheckFailed = true
            return
        }

        // `refreshQuoteUsage()` updates SessionStore's server-backed state.
        // Ask its single creation gate afterward so development builds can
        // follow the backend quota-off switch instead of re-applying the
        // numeric free allowance here.
        guard session.canCreateQuote else {
            store.isPaywallPresented = true
            return
        }

        if hasSeenRecordingIntro {
            showCreate = true
        } else {
            showRecordingIntro = true
        }
    }

    /// The announcement, raised only if it is still the only thing asking for
    /// the screen — and checked *here*, after the 0.8s wait, not before it.
    ///
    /// It was the one sheet on this view raised by a timer and the one with no
    /// guards, which is a worse combination than it sounds. Two sheets
    /// presented together are not both shown: UIKit keeps one, drops the other,
    /// and leaves the loser's `isPresented` stuck `true` with nothing on
    /// screen. Every later tap then sets a flag that is already `true`, so
    /// SwiftUI has no change to react to and the record button is dead for the
    /// rest of the launch. The window was 0.8 seconds after the quote list
    /// loaded — which is roughly when someone who opened the app to record
    /// reaches for the button.
    private func presentShareLinkNewsIfNeeded() {
        guard !seenShareLinkNews,
              !showShareLinkNews,
              session.listsLoaded,
              !session.quotes.isEmpty,
              !showRecordingIntro,
              !showCreate,
              !showCalendarIntro,
              !store.isPaywallPresented
        else { return }
        showShareLinkNews = true
    }

    /// One sheet at a time. The intro is deliberately not queued behind an
    /// announcement or another action; the person can always reach Calendar
    /// again, while a surprise stack of sheets teaches them to dismiss first.
    private func presentCalendarIntroIfNeeded() {
        guard selection == .schedule,
              !hasSeenCalendarIntro,
              !showCalendarIntro,
              session.visitStore.hasCompletedInitialSync,
              session.visitStore.visits.isEmpty,
              !showShareLinkNews,
              !showRecordingIntro,
              !showCreate,
              !store.isPaywallPresented
        else { return }
        showCalendarIntro = true
    }

    private func handleTabSelection(_ selectedTab: TabItem) {
        if selectedTab == .schedule {
            notificationRouter.clearVisitReminder()
        }
        presentCalendarIntroIfNeeded()
    }

    private var calendarIntroKey: String? {
        session.accountID.map { "hasSeenCalendarIntro-\($0.uuidString)" }
    }

    private var hasSeenCalendarIntro: Bool {
        guard let calendarIntroKey else { return true }
        return UserDefaults.standard.bool(forKey: calendarIntroKey)
    }

    private func markCalendarIntroSeen() {
        guard let calendarIntroKey else { return }
        UserDefaults.standard.set(true, forKey: calendarIntroKey)
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
        let icon = MainTabView.circularIcon(from: image, size: AppIconMetrics.tabArtwork)
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

private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
