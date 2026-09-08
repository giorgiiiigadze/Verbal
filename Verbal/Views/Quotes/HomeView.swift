//
//  HomeView.swift
//  Verbal
//
//  The "Your quotes" tab: a searchable, filterable, date-grouped list of the
//  user's quotes with pin / share / duplicate / status / delete actions.
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Store.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(AppNotificationRouter.self) private var notificationRouter
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showCreate: Bool
    @Binding var recordingVisit: ScheduledVisit?
    @Binding var savedRecordingQuoteID: UUID?
    /// Home is a preview; Calendar owns the complete visit list.
    var onShowCalendar: () -> Void = {}
    @State private var path = NavigationPath()
    @State private var quotes: [QuoteSummary] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var filter: QuoteFilter = .all
    @State private var shareTarget: QuoteSummary?
    /// Held while business details are collected; shared once that sheet closes.
    @State private var shareAfterDetails: QuoteSummary?
    /// Held while the unpriced-items warning is answered.
    @State private var shareAfterWarning: QuoteSummary?
    /// Held while the missing-client warning is answered.
    @State private var shareAfterNoClient: QuoteSummary?
    @State private var quoteToDelete: QuoteSummary?
    @State private var quoteToDuplicate: QuoteSummary?
    @State private var searchText = ""
    /// Drives the search field, because the magnifier that opens it is ours —
    /// see the toolbar group.
    @State private var isSearching = false
    /// The rate card push, driven by hand so the intro sheet can sit in front
    /// of the first one.
    @State private var showRateCard = false
    @State private var showRateCardIntro = false
    @State private var openRateCardAfterIntro = false
    /// True once the intro has been shown. Held on the device: it is about what
    /// this person has been told, not about what is on their rate card.
    @AppStorage("seenRateCardIntro") private var seenRateCardIntro = false
    /// Bumped whenever a quote arrives, to send the list back to the top.
    ///
    /// A counter rather than a flag: two arrivals in a row both have to fire,
    /// and setting a `true` that is already `true` changes nothing.
    @State private var scrollToTopToken = 0
    @State private var toast: Toast?
    /// True when the last fetch failed — distinguishes "no quotes" from
    /// "couldn't reach the server".
    @State private var loadFailed = false
    /// The currency the teaching card's sample quote is priced in, so a
    /// first-run user sees their own symbol rather than someone else's.
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue
    /// Set the first time a quote appears in this list, and never unset.
    /// Someone who deletes every quote still isn't a beginner, and the teaching
    /// card would greet them by explaining their own job back to them.
    @AppStorage("hasEverHadQuotes") private var hasEverHadQuotes = false
    /// A display preference only. Scheduled visits keep syncing and remain in
    /// the Schedule tab when this preview is hidden.
    @AppStorage(HomePreferences.upcomingVisitsVisibleKey) private var upcomingVisitsVisible = true
    /// Visits booked but not quoted yet, soonest first. Held on the device —
    /// see `ScheduledVisit`.
    @State private var visits: [ScheduledVisit] = []
    /// Non-nil while the booking sheet is up, carrying what it opened on.
    @State private var visitEditor: VisitEditor?
    /// Held while the user confirms removing a booked visit.
    @State private var visitToDelete: ScheduledVisit?
    /// The visit whose action sheet is open.
    @State private var selectedVisit: ScheduledVisit?
    /// A red visit that has been sitting for 24h and needs a decision.
    @State private var missedVisitPrompt: ScheduledVisit?
    /// Visits the user tapped "Later" on this session. Kept in memory only so
    /// the reminder returns on the next app open, but a mid-session sync that
    /// adds another visit can't spring the same alert back up seconds later.
    @State private var deferredMissedVisitIDs: Set<UUID> = []

    /// What the booking sheet opened on: nothing, or a visit already made.
    private enum VisitEditor: Identifiable {
        case new
        case existing(ScheduledVisit)

        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let visit): return visit.id.uuidString
            }
        }
    }

    private enum TimelineItem: Identifiable {
        case quote(QuoteSummary)
        case visit(ScheduledVisit)

        var id: String {
            switch self {
            case .quote(let quote): "quote-\(quote.id.uuidString)"
            case .visit(let visit): "visit-\(visit.id.uuidString)"
            }
        }
    }

    private struct TimelineSection: Identifiable {
        enum Surface: Equatable {
            case warm
            case white

            /// The two timeline surfaces are intentionally reversed only in
            /// Dark Mode, so the upcoming and saved-quote sections retain the
            /// light appearance while their dark hierarchy is swapped.
            func color(for colorScheme: ColorScheme) -> Color {
                switch (self, colorScheme) {
                case (.warm, .dark): Color(.cardSurface)
                case (.white, .dark): Color(.homeBackground)
                case (.warm, .light): Color(.homeBackground)
                case (.white, .light): Color(.cardSurface)
                @unknown default: Color(.homeBackground)
                }
            }
        }

        let title: String
        let items: [TimelineItem]
        let surface: Surface
        let id: String
    }

    private enum UpcomingVisitStatus {
        case next, upcoming, overdue

        var color: Color {
            switch self {
            case .next: Color(.statusAcceptedText)
            case .upcoming: Color(.statusWarningText)
            case .overdue: Color(.statusDeclinedText)
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .next: "Next visit"
            case .upcoming: "Upcoming visit"
            case .overdue: "Overdue visit"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            homeContent
            .background(topTimelineSurface)
            // Empty on purpose — the name of the screen is `pageTitle`, in the
            // list itself. Left as a large title it would fold into the bar on
            // scroll; left inline it would sit there permanently. Both put the
            // heading in two places at once.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Attached only while searching, so the screen carries no search
            // field until one is asked for.
            //
            // The minimized behaviour would have kept it out of the way too,
            // but the button it collapses into sits in a container of its own
            // and won't join a neighbour — which is what made the corner read
            // as two circles rather than one pill. Ours opens it instead, and
            // this stays absent until it does.
            .modifier(SearchWhenAsked(isActive: isSearching,
                                      text: $searchText,
                                      isPresented: $isSearching,
                                      prompt: "Search quotes"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Record a quote")
                }
                // The filter and the rate card, in one glass container on the
                // left, where the thumb reaching across for them is not also
                // covering the list. Both
                // are about the shape of the list rather than about a quote in
                // it — one narrows what is shown, the other holds the prices
                // that fill them — and two separate circles made them look
                // like two unrelated controls.
                //
                // The rate card used to be a tab of its own. It is setup rather
                // than a place, filled in once and topped up now and then, so
                // it was spending a permanent slot on a monthly visit.
                ToolbarItemGroup(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(QuoteFilter.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Image(.homeFilter)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    }
                    .accessibilityLabel("Filter quotes")

                    // Not a NavigationLink: the first tap has to be able to
                    // stop at the intro sheet instead of pushing.
                    Button {
                        if seenRateCardIntro {
                            showRateCard = true
                        } else {
                            showRateCardIntro = true
                        }
                    } label: {
                        Image(systemName: "tag.fill")
                    }
                    .accessibilityLabel("Rate card")
                }
            }
            .navigationDestination(for: QuoteSummary.self) { quote in
                // The row is read from the session rather than taken from the
                // pushed value, which is a snapshot of whatever the list held
                // when it was tapped.
                QuoteDetailView(
                    quote: live(quote),
                    initialLineItems: session.lineItems(for: quote.id) ?? [],
                    onDeleted: {
                        withAnimation(Self.rowRemoval) {
                            quotes.removeAll { $0.id == quote.id }
                        }
                        unlinkVisits(fromDeletedQuote: quote.id)
                        // Delay so the toast animates in on the now-visible
                        // Home, after the detail view's pop finishes (setting it
                        // mid-dismiss shows it off-screen and it's effectively
                        // missed).
                        Task {
                            try? await Task.sleep(for: .seconds(0.4))
                            toast = Toast(style: .success, message: "Quote deleted")
                        }
                    },
                    // No onRenamed or onPinChanged: both wrote by hand what the
                    // quote screen now puts in the session, which `sync` picks
                    // up — with the same spring, so a pin still lands the card
                    // in the Pinned section rather than jumping.
                    onNeedsRefresh: { Task { await load() } }
                )
                .environment(session)
                .environment(store)
                .environment(network)
            }
            .navigationDestination(isPresented: $showRateCard) {
                RateCardView()
            }
            // Continue pushes once the sheet is gone, rather than sliding a
            // screen in underneath it.
            .sheet(isPresented: $showRateCardIntro, onDismiss: {
                guard openRateCardAfterIntro else { return }
                openRateCardAfterIntro = false
                showRateCard = true
            }) {
                RateCardIntroSheet {
                    seenRateCardIntro = true
                    openRateCardAfterIntro = true
                    showRateCardIntro = false
                }
            }
            .sheet(item: $shareAfterDetails) { quote in
                BusinessDetailsSheet {
                    // Continue once the details sheet is gone, rather than
                    // stacking one on top of the other.
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))
                        confirmThenShare(quote)
                    }
                }
                .environment(session)
            }
            // Same shape as the delete and duplicate confirmations below —
            // a question, a plain action, and Cancel.
            .alert(unpricedTitle, isPresented: Binding(
                get: { shareAfterWarning != nil },
                set: { if !$0 { shareAfterWarning = nil } }
            ), presenting: shareAfterWarning) { quote in
                // Onto the client question rather than straight out, after a
                // beat: one alert can't replace another in the same breath.
                Button("Share anyway") {
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))
                        shareOrAskForClient(quote)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("They'll print as “TBC” and the total won't include them.")
            }
            // Same shape again. Cancel is the useful half: it returns them to
            // the list, where opening the quote puts the client chip in reach.
            .alert("Share without a client?", isPresented: Binding(
                get: { shareAfterNoClient != nil },
                set: { if !$0 { shareAfterNoClient = nil } }
            ), presenting: shareAfterNoClient) { quote in
                Button("Share anyway") { shareTarget = quote }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The quote will go out with no name on it. Open it to add one.")
            }
            .sheet(item: $shareTarget) { quote in
                ShareQuotePanel(quoteId: quote.id,
                                title: quote.displayTitle,
                                subtitle: "Total \(AppCurrency.format(quote.total, code: quote.currency)) · \(quote.effectiveStatus.capitalized)",
                                shareText: shareText(for: quote),
                document: pdfDocument(for: quote)) {
                    Task { await markSent(quote) }
                }
            }
            // Keep the navigation and presentation stack from making the
            // lifecycle-observer chain below one enormous generic type.
            .eraseToAnyView()
            .task {
                // Seed instantly from the data preloaded during the splash so
                // the list appears with no empty-state flash, then refresh.
                if !hasLoaded {
                    quotes = session.quotes
                    hasLoaded = session.listsLoaded
                }
                // Read here rather than at init: the store drops the days that
                // have already been and gone, and a phone left open overnight
                // would otherwise still be offering yesterday. `refresh` does
                // that with no network involved, so it still happens in a loft.
                session.visitStore.refresh()
                visits = session.visitStore.visits
                promptForMissedVisitIfNeeded()
                await load()
                await openPendingNotificationQuoteIfNeeded()
            }
            .modifier(SessionSync(quotes: session.quotes,
                                  listsLoaded: session.listsLoaded,
                                  apply: sync))
            .modifier(VisitSync(visits: session.visitStore.visits,
                                isOnline: network.isOnline,
                                apply: applyVisits,
                                reconnected: { Task { await session.visitStore.sync() } }))
            .onChange(of: quotes.isEmpty) { _, isEmpty in
                if !isEmpty { hasEverHadQuotes = true }
            }
            .onChange(of: visits) { _, _ in
                promptForMissedVisitIfNeeded()
            }
            .onChange(of: notificationRouter.requestedQuoteId) { _, quoteId in
                handleRequestedQuoteChange(quoteId)
            }
            .onChange(of: savedRecordingQuoteID) { _, quoteId in
                handleSavedRecordingQuoteChange(quoteId)
            }
            .onChange(of: showCreate) { _, isPresented in
                handleCreatePresentationChange(isPresented)
            }
            .refreshable { await load() }
            .alert("Delete this quote?", isPresented: isDeleteQuoteAlertPresented,
                   presenting: quoteToDelete) { quote in
                Button("Delete", role: .destructive) {
                    Task { await delete(quote) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { quote in
                Text("This permanently deletes “\(quote.displayTitle)”. This can't be undone.")
            }
            .alert("Duplicate this quote?", isPresented: isDuplicateQuoteAlertPresented,
                   presenting: quoteToDuplicate) { quote in
                Button("Duplicate") {
                    Task { await duplicate(quote) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { quote in
                Text("This creates a copy of “\(quote.displayTitle)” as a new draft.")
            }
        }
        .toast($toast)
        .modifier(VisitDeleteConfirmation(visit: $visitToDelete, onDelete: remove))
        .modifier(MissedVisitConfirmation(visit: $missedVisitPrompt,
                                           onRecord: { visit in
            beginRecording(for: visit)
        },
                                           onDidNotHappen: markPromptedAndClear,
                                           onLater: { visit in
            deferredMissedVisitIDs.insert(visit.id)
        }))
        .sheet(item: $selectedVisit) { visit in
            let currentVisit = live(visit)
            VisitActionSheet(
                visit: currentVisit,
                action: visitAction(for: currentVisit),
                onPrimary: { performPrimaryVisitAction(currentVisit) },
                onDirections: { openDirections(for: currentVisit) },
                onCall: { callClient(for: currentVisit) },
                onReschedule: { visitEditor = .existing(currentVisit) },
                onCancel: { visitToDelete = currentVisit },
                onDidNotHappen: { missedVisitPrompt = currentVisit },
                onOpenQuote: { openRecordedQuote(for: currentVisit) }
            )
        }
        // The booking wizard is a large sheet: it preserves Home underneath
        // while giving the calendar and time picker the room they need.
        .sheet(item: $visitEditor) { editor in
            switch editor {
            case .new:
                ScheduleVisitSheet(onSave: addOrUpdate)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            case .existing(let visit):
                ScheduleVisitSheet(editing: visit,
                                   onSave: addOrUpdate,
                                   onDelete: remove)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if quotes.isEmpty && !hasLoaded {
            // Still loading first paint — placeholders, not "no quotes".
            loadingState
        } else if quotes.isEmpty && loadFailed {
            // Don't claim the account is empty when the fetch failed.
            errorState
        } else if quotes.isEmpty && timelineVisits.isEmpty {
            emptyState
        } else if !quotes.isEmpty && sections.isEmpty {
            // Quotes exist, but the search or filter excluded them all.
            noMatchesState
        } else {
            // Also the no-quotes-but-visits-booked case: the list is the only
            // screen the upcoming section lives on.
            quotesList
        }
    }

    /// The first-quote card already contains the primary recording action.
    /// Showing the floating control beside it creates two identical calls to
    /// action on one screen.
    private var showsFirstQuoteCard: Bool {
        quotes.isEmpty && timelineVisits.isEmpty && hasLoaded && !loadFailed && !hasEverHadQuotes
    }

    private var isDeleteQuoteAlertPresented: Binding<Bool> {
        Binding(get: { quoteToDelete != nil }, set: { if !$0 { quoteToDelete = nil } })
    }

    private var isDuplicateQuoteAlertPresented: Binding<Bool> {
        Binding(get: { quoteToDuplicate != nil }, set: { if !$0 { quoteToDuplicate = nil } })
    }

    private func handleRequestedQuoteChange(_ quoteId: UUID?) {
        guard let quoteId else { return }
        Task { await openQuoteFromNotification(id: quoteId) }
    }

    private func handleSavedRecordingQuoteChange(_ quoteId: UUID?) {
        handleSavedRecordingQuote(quoteId)
    }

    private func handleCreatePresentationChange(_ isPresented: Bool) {
        handleRecorderPresentationChange(isPresented: isPresented)
    }

    /// An upcoming-visit section begins at the very top of Home, so its
    /// surface continues behind the title and toolbar instead of starting at a
    /// visible horizontal seam. In Light Mode this resolves to the same
    /// existing Home background; in Dark Mode it uses the swapped visit tone.
    private var topTimelineSurface: Color {
        guard !timelineVisits.isEmpty else { return Color(.homeBackground) }
        return TimelineSection.Surface.warm.color(for: colorScheme)
    }

    // MARK: - List

    /// The screen's name, set as the page's own heading rather than as a
    /// navigation title.
    ///
    /// It scrolls away with the list and never reappears in the bar. A large
    /// title would collapse into the bar on the way up, which puts the name of
    /// the screen you are already on back in front of you — and the bar has
    /// the filter, the rate card and search in it, which are the things worth
    /// reaching for once the list is moving.
    private var pageTitle: some View {
        Text("Your quotes")
            .font(.robotoSlab(30, relativeTo: .title))
            .foregroundStyle(Color(.mainText))
            .id(Self.topAnchor)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
    }

    private var quotesList: some View {
        ScrollViewReader { proxy in
            List {
                pageTitle

                if upcomingVisitsVisible, filter == .all,
                   searchQuery.isEmpty, timelineVisits.isEmpty {
                    upcomingVisitsEmptyCard
                }

                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    // Header as a normal row (not a Section header) so it scrolls
                    // away with the content instead of pinning to the top.
                    Text(section.title)
                        // A shade heavier than the body around it. Not darker as
                        // well: a date carries less than a status heading did, and
                        // it only has to mark where one day ends and the next
                        // begins.
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .listRowBackground(section.surface.color(for: colorScheme))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))

                    ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                        let closesWarmSurface = section.surface == .warm
                            && sections.indices.contains(index + 1)
                            && sections[index + 1].surface == .white
                            && itemIndex == section.items.indices.last

                        switch item {
                        case .quote(let quote):
                            quoteTimelineRow(quote, surface: section.surface)
                        case .visit(let visit):
                            visitRow(visit,
                                     surface: section.surface,
                                     bottomInset: closesWarmSurface ? 14 : 5)
                        }
                    }

                    if section.id == lastUpcomingSectionID,
                       upcomingVisitOverflowCount > 0 {
                        upcomingVisitOverflowRow
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Room under the last row for the floating tab bar, which draws
            // over the list rather than beside it. Without this the bottom
            // quote is permanently cut in half, and the one below it is the one
            // you can never quite reach. The Record safe-area inset adds its
            // own 50-point height and 12-point gap above this margin.
            .contentMargins(.bottom, 88, for: .scrollContent)
            // Back to the top when a quote arrives — see `load()`. The token is
            // what carries the news down here, since `load()` has no way to
            // reach the proxy.
            .onChange(of: scrollToTopToken) { _, _ in
                withAnimation(Self.rowInsert) {
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
        }
    }

    private var upcomingVisitsEmptyCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.statusMutedText))
                .frame(width: 36, height: 36)
                .background(Color(.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("No upcoming visits yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text("Book a visit and it will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 68)
        .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        }
        .listRowBackground(Color(.homeBackground))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 14, trailing: 20))
    }

    private var upcomingVisitOverflowRow: some View {
        Button(action: onShowCalendar) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                Text("See \(upcomingVisitOverflowCount) more upcoming \(upcomingVisitOverflowCount == 1 ? "visit" : "visits")")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(OnboardingStyle.action)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(upcomingVisitCardFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See \(upcomingVisitOverflowCount) more upcoming visits in Calendar")
        .listRowBackground(TimelineSection.Surface.warm.color(for: colorScheme))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 14, trailing: 20))
    }

    private func quoteTimelineRow(_ quote: QuoteSummary,
                                  surface: TimelineSection.Surface) -> some View {
        ZStack {
            QuoteRow(quote: quote, unpricedCount: unpricedCount(for: quote))
            NavigationLink(value: quote) { EmptyView() }
                .opacity(0)
        }
        .listRowBackground(surface.color(for: colorScheme))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 5, trailing: 20))
        .onAppear {
            Task { await session.prefetchLineItems(for: quote.id) }
        }
        .contextMenu { quoteMenu(for: quote) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                quoteToDelete = quote
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func hasRecordedQuote(for visit: ScheduledVisit) -> Bool {
        if let id = visit.recordedQuoteId {
            return quotes.contains { $0.id == id } || session.quotes.contains { $0.id == id }
        }
        let visitKey = visit.clientKey
        guard !visitKey.isEmpty else { return false }
        return quotes.contains { quote in
            Calendar.current.isDate(quote.createdAt, inSameDayAs: visit.date)
                && (quote.displayTitle.lowercased() == visitKey
                    || quote.clientName?.lowercased() == visitKey)
        }
    }

    /// One booked visit, drawn as the quote rows are drawn: the list has one
    /// row language, and a visit is a quote that hasn't been spoken yet.
    private func visitRow(_ visit: ScheduledVisit,
                          surface: TimelineSection.Surface,
                          bottomInset: CGFloat = 5) -> some View {
        let status = upcomingVisitStatus(for: visit)

        return Button {
            selectedVisit = visit
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.statusMutedText))
                    .frame(width: 36, height: 36)
                    .background(Color(.surface), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(visit.title)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)

                    // Who it's for, quietly under the name of the job. Only
                    // when there is one — visits booked before clients had a
                    // field of their own already say the name in the title.
                    if let client = visit.clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !client.isEmpty {
                        Text(client)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let note = visit.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(visit.timeText)
                        .monospacedDigit()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.surface), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Tall enough for iOS to draw the swipe actions as icon-above-label,
            // matching the quote rows below — see the same frame on `QuoteRow`.
            .frame(minHeight: 68)
            .background(upcomingVisitCardFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(status.color)
                    .frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(visit.accessibilityText). \(status.accessibilityLabel). Record a quote")
        .listRowBackground(surface.color(for: colorScheme))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: bottomInset, trailing: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                visitToDelete = visit
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                visitEditor = .existing(visit)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color(.statusMutedText))
        }
    }

    /// Upcoming visits sit on the lighter Dark Mode timeline surface. Giving
    /// their containers this near-black fill keeps that section layered without
    /// changing the existing white appearance in Light Mode.
    private var upcomingVisitCardFill: Color {
        colorScheme == .dark
            ? Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
            : Color(.cardSurface)
    }

    /// Match Calendar's two-hour grace period before an unquoted appointment
    /// becomes overdue. The next non-overdue appointment gets the calmer green
    /// rail so it is the one the user can find at a glance.
    private func upcomingVisitStatus(for visit: ScheduledVisit) -> UpcomingVisitStatus {
        if isVisitOverdue(visit) {
            return .overdue
        }
        return timelineVisits.first?.id == visit.id ? .next : .upcoming
    }

    /// Take a list that arrived from the server: booked on another phone, or
    /// pushed from this one after it found signal again.
    ///
    /// A pull that changes nothing must look like nothing, which is what the
    /// guard is for — the same rule `load()` follows for quotes.
    private func applyVisits(_ fresh: [ScheduledVisit]) {
        guard fresh != visits else { return }
        visits = fresh
        promptForMissedVisitIfNeeded()
    }

    /// New booking, or a correction to one. Sorted on the way in so the list
    /// and the stored copy are always in the order they're read in.
    private func addOrUpdate(_ visit: ScheduledVisit) {
        session.visitStore.addOrUpdate(visit)
        withAnimation(Self.rowInsert) {
            visits = session.visitStore.visits
        }
        Task { await ScheduledVisitNotifications.schedule(visit) }
    }

    private func remove(_ visit: ScheduledVisit) {
        session.visitStore.remove(visit)
        withAnimation(Self.rowRemoval) {
            visits = session.visitStore.visits
        }
        ScheduledVisitNotifications.cancel(visit)
        if visits.isEmpty {
            selectedVisit = nil
        }
        toast = Toast(style: .success, message: "Visit removed")
    }

    private func live(_ visit: ScheduledVisit) -> ScheduledVisit {
        visits.first { $0.id == visit.id } ?? visit
    }

    private func visitAction(for visit: ScheduledVisit) -> VisitAction {
        if hasRecordedQuote(for: visit) {
            return .recorded(recordedQuote(for: visit))
        }

        let now = Date()
        if now >= visit.date.addingTimeInterval(-15 * 60),
           now <= visit.date.addingTimeInterval(30 * 60) {
            return .happeningNow
        }
        if visit.date < now {
            return .passed
        }
        return .future
    }

    private func recordedQuote(for visit: ScheduledVisit) -> QuoteSummary? {
        if let id = visit.recordedQuoteId {
            return quotes.first { $0.id == id } ?? session.quotes.first { $0.id == id }
        }

        let visitKey = visit.clientKey
        guard !visitKey.isEmpty else { return nil }
        return quotes.first { quote in
            Calendar.current.isDate(quote.createdAt, inSameDayAs: visit.date)
                && (quote.displayTitle.lowercased() == visitKey
                    || quote.clientName?.lowercased() == visitKey)
        }
    }

    private func performPrimaryVisitAction(_ visit: ScheduledVisit) {
        switch visitAction(for: visit) {
        case .future:
            openDirections(for: visit)
        case .happeningNow, .passed:
            beginRecording(for: visit)
        case .recorded:
            openRecordedQuote(for: visit)
        }
    }

    private func beginRecording(for visit: ScheduledVisit) {
        selectedVisit = nil
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            recordingVisit = visit
            showCreate = true
        }
    }

    /// A quote has been saved from the recorder.
    ///
    /// `MainTabView` has already linked it to the visit it was recorded for —
    /// that is the one place both Home and Calendar route through. All that is
    /// left here is to take the prompt down and repaint the row as recorded.
    ///
    /// Recording from the missed-visit prompt used to *delete* the visit at
    /// this point, on top of the link that had just been made: the booking
    /// vanished from Calendar's Recorded filter, and deleting the quote later
    /// had no visit left to hand back. The ordinary "Record now" path keeps the
    /// linked visit until its day is over, and this one now does the same.
    private func handleSavedRecordingQuote(_ quoteId: UUID?) {
        guard quoteId != nil else { return }
        missedVisitPrompt = nil
        if let recordingVisit {
            deferredMissedVisitIDs.remove(recordingVisit.id)
        }
        withAnimation(Self.rowInsert) {
            visits = session.visitStore.visits
        }
        savedRecordingQuoteID = nil
    }

    private func handleRecorderPresentationChange(isPresented: Bool) {
        guard !isPresented else { return }
        recordingVisit = nil
        Task { await load() }
    }

    private func unlinkVisits(fromDeletedQuote quoteId: UUID) {
        // The store hands back the visits it released, already unlinked.
        let unlinked = session.visitStore.unlink(fromDeletedQuote: quoteId)
        guard !unlinked.isEmpty else { return }

        withAnimation(Self.rowRemoval) {
            visits = session.visitStore.visits
        }

        Task {
            for visit in unlinked {
                await ScheduledVisitNotifications.schedule(visit)
            }
        }
    }

    private func markPromptedAndClear(_ visit: ScheduledVisit) {
        missedVisitPrompt = nil
        ScheduledVisitNotifications.cancel(visit)
        session.visitStore.markPromptedAndClear(visit)
        withAnimation(Self.rowRemoval) {
            visits = session.visitStore.visits
        }
    }

    private func promptForMissedVisitIfNeeded() {
        guard missedVisitPrompt == nil else { return }
        missedVisitPrompt = visits.first { visit in
            !hasRecordedQuote(for: visit)
                && !visit.didPromptForMissedVisit
                && !deferredMissedVisitIDs.contains(visit.id)
                && Date() >= visit.date.addingTimeInterval(24 * 60 * 60)
        }
    }

    private func openRecordedQuote(for visit: ScheduledVisit) {
        guard let quote = recordedQuote(for: visit) else {
            toast = Toast(style: .error, message: "Couldn't find that quote")
            return
        }
        selectedVisit = nil
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            path.append(quote)
        }
    }

    private func openPendingNotificationQuoteIfNeeded() async {
        guard let quoteId = notificationRouter.requestedQuoteId else { return }
        await openQuoteFromNotification(id: quoteId)
    }

    private func openQuoteFromNotification(id quoteId: UUID) async {
        var quote = quotes.first { $0.id == quoteId } ?? session.quotes.first { $0.id == quoteId }
        if quote == nil {
            await load()
            quote = quotes.first { $0.id == quoteId } ?? session.quotes.first { $0.id == quoteId }
        }

        guard let quote else {
            notificationRouter.clearQuoteRequest(id: quoteId)
            toast = Toast(style: .error, message: "Couldn't find that quote")
            return
        }

        await session.prefetchLineItems(for: quote.id)
        selectedVisit = nil
        path = NavigationPath()
        path.append(quote)
        notificationRouter.clearQuoteRequest(id: quoteId)
    }

    private func openDirections(for visit: ScheduledVisit) {
        guard let address = visit.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else {
            toast = Toast(style: .error, message: "No address saved")
            return
        }
        openURL(url)
    }

    private func callClient(for visit: ScheduledVisit) {
        guard let phone = visit.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phone.isEmpty else {
            toast = Toast(style: .error, message: "No phone number saved")
            return
        }

        let dialable = phone.filter { character in
            character.isNumber || character == "+"
        }
        guard !dialable.isEmpty, let url = URL(string: "tel:\(dialable)") else {
            toast = Toast(style: .error, message: "Couldn't call this number")
            return
        }

        openURL(url)
    }

    /// Long-press context menu for a quote card.
    @ViewBuilder
    private func quoteMenu(for quote: QuoteSummary) -> some View {
        Button {
            Task { await togglePin(quote) }
        } label: {
            Label(quote.pinned ? "Unpin" : "Pin",
                  systemImage: quote.pinned ? "pin.slash" : "pin")
        }
        Button {
            share(quote)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            quoteToDuplicate = quote
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Menu {
            ForEach(selectableStatuses, id: \.self) { option in
                Button {
                    Task { await changeStatus(quote, to: option) }
                } label: {
                    Label(statusLabel(for: option), systemImage: statusIcon(for: option))
                }
            }
        } label: {
            Label("Status", systemImage: "arrow.triangle.2.circlepath")
        }
        Divider()
        Button(role: .destructive) {
            quoteToDelete = quote
        } label: {
            Label {
                Text("Delete")
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    /// First run: an invitation into the core loop, not a note that the list
    /// is empty. This is the screen a new user meets straight after onboarding.
    /// Two different screens, not two versions of one. A first quote is worth
    /// selling; an empty list belonging to someone who has made fifty is just a
    /// state, and dressing it up as an announcement is the app talking when it
    /// has nothing to say.
    @ViewBuilder
    private var emptyState: some View {
        if hasEverHadQuotes {
            // The same shape the rate card uses when it has been emptied, and
            // for the same reason: this user knows what a quote is.
            //
            // Keep this inline action quiet: the blue Record pill is already
            // floating nearby, and two equally prominent invitations would
            // turn an empty screen into a choice between identical actions.
            EmptyStateMessage(
                icon: "waveform",
                assetIcon: "QuotesEmpty",
                title: "No quotes right now",
                message: "Describe the next job out loud and it'll be priced and waiting here."
            ) {
                EmptyStatePill(title: "Record a quote", icon: "mic.fill") {
                    showCreate = true
                }
            }
        } else {
            firstQuoteCard
        }
    }

    /// The first-run screen. Worth its own container: it has something to show
    /// and something to teach, and neither survives being reduced to a line.
    private var firstQuoteCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                // The product, drawn the way the app already draws it. A
                // photograph here would be borrowed atmosphere; a quote is the
                // thing they came for, and seeing its shape answers "what do I
                // get out of this?" before they've said a word.
                sampleQuote
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .frame(height: 158, alignment: .top)
                    .clipped()
                    // Fades into the copy instead of stopping at a hard edge,
                    // so it reads as a backdrop rather than a real row.
                    .mask(
                        LinearGradient(colors: [.black, .black, .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Your first quote starts here")
                        .font(.robotoSlab(22, relativeTo: .title3))
                        .foregroundStyle(Color(.mainText))
                        .multilineTextAlignment(.center)

                    // The one thing a new user can't guess: that they should
                    // talk in numbers. Without it the first attempt is vague,
                    // comes back as "not enough detail", and that is the worst
                    // possible first impression of the whole idea.
                    Text("Try saying: \u{201C}Re-tile the bathroom floor, eighteen square metres at forty-five a metre, and replace the toilet for ninety.\u{201D}")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    recordButton
                        .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.royalBlue25),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )

            Text("Quotes you make are saved here. Share one as a PDF when it's ready.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        // The same inset the quote rows sit at, so an empty list and a full one
        // occupy the same column.
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }

    private var recordButton: some View {
        Button {
            showCreate = true
        } label: {
            HStack(spacing: 8) {
                Image("RecordingIntro")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text("Record a quote").fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .background(Color(.royalBlue600),
                        in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// A quote that doesn't exist, in the user's own currency.
    private var sampleQuote: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bathroom re-tiling")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(AppCurrency.format(1240, code: currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
            }
            .padding(.bottom, 10)

            ForEach(Self.sampleLines, id: \.name) { line in
                Divider()
                HStack {
                    Text(line.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(AppCurrency.format(line.amount, code: currencyCode))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    /// Sums to the total above — a demo that doesn't add up would be a poor
    /// advertisement for a quoting app.
    private static let sampleLines: [(name: String, amount: Double)] = [
        ("Re-tiling bathroom floor", 810),
        ("Mixer taps", 340),
        ("Replacement toilet", 90)
    ]

    /// Stand-in rows for the moment before the first fetch lands. The splash
    /// stops waiting on the lists after two seconds so a slow launch still gets
    /// in, and what followed that was a blank page — which reads as an app that
    /// broke rather than one that is loading.
    private var loadingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                skeletonBar(width: 178, height: 34)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                skeletonSectionHeader(width: 96)
                    .padding(.top, 2)

                ForEach(Array(Self.skeletonWidths.enumerated()), id: \.offset) { _, width in
                    QuoteRowSkeleton(titleWidth: width)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 88)
        }
        // One sweep travelling across the whole stack, not four in step.
        .shimmer(active: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your quotes")
    }

    private func skeletonSectionHeader(width: CGFloat) -> some View {
        skeletonBar(width: width, height: 14)
            .padding(.vertical, 6)
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
    }

    /// Varied so the placeholders read as quotes rather than as a repeated tile.
    private static let skeletonWidths: [CGFloat] = [168, 124, 196, 142]

    /// Enough overshoot to feel alive, damped enough not to wobble — this fires
    /// on a list the user is reading, not on a splash screen.
    private static let pinSpring = Animation.spring(response: 0.34, dampingFraction: 0.62)

    /// Removal gets no bounce. A row leaving should close up behind itself, not
    /// spring — the quote is gone and the motion shouldn't be cheerful about it.
    static let rowRemoval = Animation.easeInOut(duration: 0.28)

    /// Arriving does get a little. A quote that has just been spoken into
    /// existence is the one thing on this screen worth a spring.
    private static let rowInsert = Animation.snappy(duration: 0.35)

    /// The row the list scrolls back to when a quote arrives.
    private static let topAnchor = "top"

    /// Quotes exist but the active search or filter matched none of them.
    private var noMatchesState: some View {
        placeholder(
            icon: "magnifyingglass",
            title: "Nothing to show",
            message: searchQuery.isEmpty
                ? "No quotes are \(filter.label.lowercased()) right now."
                : "No quotes match “\(searchQuery)”."
        ) {
            Button("Clear search and filters") {
                searchText = ""
                filter = .all
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(.blueAccentText))
        }
    }

    /// The first load failed and there's nothing cached to fall back on.
    private var errorState: some View {
        placeholder(
            icon: "wifi.exclamationmark",
            title: "Couldn't load your quotes",
            message: "Check your connection and try again."
        ) {
            Button("Try again") {
                Task { await load() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(.blueAccentText))
        }
    }

    /// Shared centered layout for the empty / no-match / error screens.
    private func placeholder<Action: View>(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(.mainText))
                .padding(.bottom, 6)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(.mainText))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            action()
                .padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    /// The trimmed search text, as typed (for display in the no-match state).
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Booked work stays in the Home timeline without becoming a separate card.
    /// Upcoming work stays on the warm surface; pinned and historical quotes
    /// continue on white.
    private var sections: [TimelineSection] {
        let query = searchQuery.lowercased()
        let filtered = quotes.filter { quote in
            guard filter.matches(quote.effectiveStatus) else { return false }
            guard !query.isEmpty else { return true }
            return quote.displayTitle.lowercased().contains(query)
                || (quote.jobSummary?.lowercased().contains(query) ?? false)
        }
        let pinned = filtered.filter(\.pinned)
        let rest = filtered.filter { !$0.pinned }
        let calendar = Calendar.current
        var quoteDays: [Date: [TimelineItem]] = [:]
        for quote in rest {
            quoteDays[calendar.startOfDay(for: quote.createdAt), default: []].append(.quote(quote))
        }
        var visitDays: [Date: [TimelineItem]] = [:]
        for visit in timelineVisits {
            visitDays[calendar.startOfDay(for: visit.date), default: []].append(.visit(visit))
        }

        var result = visitDays.keys.sorted().map { day in
            TimelineSection(title: upcomingVisitSectionTitle(day),
                            items: (visitDays[day] ?? []).sorted { left, right in
                                guard case .visit(let lhs) = left,
                                      case .visit(let rhs) = right else { return false }
                                return lhs.date < rhs.date
                            },
                            surface: .warm,
                            id: "visit-day-\(day.timeIntervalSince1970)")
        }
        if !pinned.isEmpty {
            result.append(TimelineSection(
                title: "Pinned",
                items: pinned.map(TimelineItem.quote),
                surface: .white,
                id: "pinned"
            ))
        }

        result += quoteDays.keys.sorted(by: >).map { day in
            return TimelineSection(title: quoteSectionTitle(day),
                                   items: quoteDays[day] ?? [],
                                   surface: .white,
                                   id: "quote-day-\(day.timeIntervalSince1970)")
        }
        return result
    }

    /// Historical quotes use “Earlier today,” but a booked visit later today
    /// must not be described as already past. Keep upcoming appointments in
    /// their own, forward-looking date language.
    private func upcomingVisitSectionTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let daysAway = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if daysAway < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var allUpcomingVisits: [ScheduledVisit] {
        guard filter == .all, upcomingVisitsVisible else { return [] }
        let query = searchQuery.lowercased()
        return visits
            .filter { $0.endDate >= Date() && !hasRecordedQuote(for: $0) }
            .filter { visit in
                guard !query.isEmpty else { return true }
                return visit.title.lowercased().contains(query)
                    || (visit.clientName?.lowercased().contains(query) ?? false)
            }
            .sorted { $0.date < $1.date }
    }

    /// Home is an at-a-glance preview, not another full calendar. Keep the
    /// next three appointments and surface any overdue visit even when it
    /// would otherwise fall outside that compact preview.
    private var timelineVisits: [ScheduledVisit] {
        let nextThreeIDs = Set(allUpcomingVisits
            .filter { !isVisitOverdue($0) }
            .prefix(3)
            .map(\.id))
        return allUpcomingVisits.filter {
            nextThreeIDs.contains($0.id) || isVisitOverdue($0)
        }
    }

    private var upcomingVisitOverflowCount: Int {
        max(0, allUpcomingVisits.count - timelineVisits.count)
    }

    private var lastUpcomingSectionID: String? {
        sections.last(where: { $0.surface == .warm })?.id
    }

    private func isVisitOverdue(_ visit: ScheduledVisit) -> Bool {
        Date() >= visit.date.addingTimeInterval(2 * 60 * 60)
    }

    // MARK: - Data

    /// Load the line items (usually already prefetched by the row) before
    /// opening the share panel — without them the PDF would print an empty
    /// table, so this waits rather than rendering a half-built document.
    private func share(_ quote: QuoteSummary) {
        guard requireInternetForSharing() else { return }

        Task {
            await session.prefetchLineItems(for: quote.id)
            // Last chance to put a name on the document before a customer reads
            // it. Whatever they choose, the share still happens.
            if BusinessPrompt.shouldAsk(session.businessProfile) {
                shareAfterDetails = quote
            } else {
                confirmThenShare(quote)
            }
        }
    }

    /// Warn when the quote still has gaps, then share either way. Never blocks:
    /// a price the supplier hasn't given yet is a normal thing to send as TBC.
    private func confirmThenShare(_ quote: QuoteSummary) {
        if unpricedCount(for: quote) > 0 {
            shareAfterWarning = quote
        } else {
            shareOrAskForClient(quote)
        }
    }

    /// The last gate, matching the quote screen's. A fully priced quote with no
    /// name at the top is a document the customer can't tell was written for
    /// them, and the transcript often doesn't carry that detail.
    private func shareOrAskForClient(_ quote: QuoteSummary) {
        guard requireInternetForSharing() else { return }

        if (quote.clientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shareAfterNoClient = quote
        } else {
            shareTarget = quote
        }
    }

    private func requireInternetForSharing() -> Bool {
        guard network.isOnline else {
            toast = Toast(style: .error, message: "Internet required for sharing")
            return false
        }
        return true
    }

    /// Reads the line items prefetched just before this — the summary row alone
    /// doesn't know what's inside a quote.
    private func unpricedCount(for quote: QuoteSummary) -> Int {
        (session.lineItems(for: quote.id) ?? []).filter(\.isMissingPrice).count
    }

    private var unpricedTitle: String {
        let count = shareAfterWarning.map(unpricedCount(for:)) ?? 0
        return "Share with \(count) item\(count == 1 ? "" : "s") unpriced?"
    }

    /// The quote as a printable document, for the share panel's PDF.
    private func pdfDocument(for quote: QuoteSummary) -> QuoteDocument {
        QuoteDocument(
            title: quote.displayTitle,
            number: quote.numberText(prefix: session.businessProfile?.quoteNumberPrefix),
            clientName: quote.clientName,
            clientAddress: clientVisitAddress(for: quote),
            clientPhone: clientVisitPhone(for: quote),
            createdAt: quote.createdAt,
            validityDate: quote.validityDate,
            jobSummary: quote.jobSummary,
            scope: quote.scope,
            lineItems: session.lineItems(for: quote.id) ?? [],
            subtotal: quote.subtotal,
            taxRate: quote.taxRate,
            taxAmount: quote.taxAmount,
            total: quote.total,
            currency: quote.currency,
            business: session.businessProfile
        )
    }

    /// Quotes only retain a client's name. A booked visit can also carry the
    /// address and phone the user has already collected, so reuse those facts
    /// in a document rather than making the recipient block look unfinished.
    private func clientVisits(for quote: QuoteSummary) -> [ScheduledVisit] {
        let name = quote.clientName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !name.isEmpty else { return [] }
        return visits
            .filter { $0.clientKey.contains(name) }
            .sorted { $0.date > $1.date }
    }

    private func clientVisitAddress(for quote: QuoteSummary) -> String? {
        clientVisits(for: quote)
            .compactMap { cleanedClientDetail($0.address) }
            .first
    }

    private func clientVisitPhone(for quote: QuoteSummary) -> String? {
        clientVisits(for: quote)
            .compactMap { cleanedClientDetail($0.phone) }
            .first
    }

    private func cleanedClientDetail(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shareText(for quote: QuoteSummary) -> String {
        var lines = [quote.displayTitle]
        if let summary = quote.jobSummary, !summary.isEmpty { lines.append(summary) }
        return lines.joined(separator: "\n")
    }

    /// The quote as the session has it now, rather than as it was when the row
    /// was tapped.
    private func live(_ quote: QuoteSummary) -> QuoteSummary {
        session.quotes.first { $0.id == quote.id } ?? quote
    }

    /// Keep this screen's list in step with the session's.
    ///
    /// An edit made on the quote screen goes into the session, not into this
    /// array — so the changed rows are taken from it rather than each field
    /// being announced by a callback per screen that wants one.
    ///
    /// Matched by id and applied in place: Home owns the order, the sections
    /// and its own fetch, and swallowing the session's whole list would throw
    /// away a filter or a search that is on screen.
    ///
    /// The exception is the empty case. Bootstrap can finish after this view
    /// has already read an empty list — signing in reaches Home before the
    /// preload returns — and there is nothing to match against, so what arrives
    /// is taken whole.
    private func sync(_ fresh: [QuoteSummary], _ listsLoaded: Bool) {
        if quotes.isEmpty {
            guard listsLoaded, !fresh.isEmpty else { return }
            quotes = fresh
            loadFailed = false
            promptForMissedVisitIfNeeded()
            Task { await QuoteExpiryNotifications.rescheduleAll(quotes: quotes) }
            return
        }
        for updated in fresh {
            guard let index = quotes.firstIndex(where: { $0.id == updated.id }),
                  quotes[index] != updated else { continue }
            withAnimation(Self.pinSpring) { quotes[index] = updated }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await fetchAllowingOneRetry()
            // Only when something turned up that wasn't here before. A refresh
            // that changes nothing must look like nothing, and `hasLoaded`
            // keeps the first paint still — animating that would slide the
            // whole list in on every cold start, which is a different feature
            // and a worse one.
            let arrived = hasLoaded && fresh.contains { new in
                !quotes.contains { $0.id == new.id }
            }
            if arrived {
                withAnimation(Self.rowInsert) { quotes = fresh }
                // Nothing to see if it landed above the viewport — and worse
                // than nothing, since the recording then looks like it failed.
                scrollToTopToken += 1
            } else {
                quotes = fresh
            }
            promptForMissedVisitIfNeeded()
            loadFailed = false
            // Push the authoritative list into the session so the Clients tab —
            // drawn from it — shows a just-made quote (and its client) without
            // waiting for the next launch.
            session.setQuotes(quotes)
            await QuoteExpiryNotifications.rescheduleAll(quotes: quotes)
        } catch {
            // A load that was cancelled did not fail. `.task` is cancelled the
            // moment this view goes away — tapping a quote, switching tab,
            // opening the recorder — and the request in flight throws for that
            // reason. Reporting it put a red cross on screen for the ordinary
            // act of tapping something, which is exactly why it looked random:
            // it depended on whether you touched anything during the fraction
            // of a second the fetch takes.
            guard !error.isCancellation else { return }
            // Keep whatever we had on screen; the flag lets the empty state
            // report a failure instead of claiming there are no quotes.
            loadFailed = true
            // Silent with no connection. The offline banner is already on
            // screen saying exactly this, and a red toast over the top tells
            // the user off twice for the same thing.
            if !quotes.isEmpty, network.isOnline {
                toast = Toast(style: .error, message: "Couldn't refresh quotes")
            }
        }
        hasLoaded = true
    }

    /// Cold launch lands on this screen deliberately holding a token that may
    /// have expired — it is refreshed underneath rather than blocking first
    /// paint — and this load races the one bootstrap starts at the same moment.
    /// Either can arrive inside that window and come back unauthorised.
    ///
    /// Bootstrap's copy swallows that with `try?` and says nothing, so the same
    /// transient failure was invisible on one path and a red cross on the
    /// other. A single retry after a beat is long enough for a refresh already
    /// in flight to land.
    private func fetchAllowingOneRetry() async throws -> [QuoteSummary] {
        do {
            return try await QuoteService.fetchQuotes()
        } catch {
            // Don't wait out a retry for a load nobody is waiting on any more.
            guard !error.isCancellation else { throw error }
            try await Task.sleep(for: .milliseconds(600))
            return try await QuoteService.fetchQuotes()
        }
    }

    private func delete(_ quote: QuoteSummary) async {
        do {
            try await QuoteService.deleteQuote(id: quote.id)
            QuoteExpiryNotifications.cancel(quote)
            // Also drop it from the shared list, so the Clients tab (drawn from
            // it) loses the quote too, not just this screen's own copy.
            session.removeQuote(id: quote.id)
            unlinkVisits(fromDeletedQuote: quote.id)
            // Every other mutation here animates; a row that simply blinks out
            // makes the list look like it lost its place rather than obeyed.
            withAnimation(Self.rowRemoval) { quotes.removeAll { $0.id == quote.id } }
            toast = Toast(style: .success, message: "Quote deleted")
        } catch {
            toast = Toast(style: .error, message: "Couldn't delete quote")
        }
    }

    /// Sharing a draft marks it as Sent (don't downgrade later statuses).
    private func markSent(_ quote: QuoteSummary) async {
        guard quote.status == "draft" else { return }
        do {
            try await QuoteService.updateStatus(id: quote.id, status: "sent")
            await load()
        } catch {
            // Keep the current status if the update failed.
        }
    }

    // MARK: - Context-menu actions

    /// Statuses offered in the status submenu, in workflow order.
    private let selectableStatuses = ["draft", "sent", "viewed", "accepted", "declined", "expired"]

    private func statusLabel(for status: String) -> String {
        switch status {
        case "draft": return "Draft"
        case "sent": return "Sent"
        case "viewed": return "Viewed"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "expired": return "Expired"
        default: return status.capitalized
        }
    }

    private func statusIcon(for status: String) -> String {
        switch status {
        case "draft": return "pencil"
        case "sent": return "paperplane"
        case "viewed": return "eye"
        case "accepted": return "checkmark.circle"
        case "declined": return "xmark.circle"
        case "expired": return "clock.badge.exclamationmark"
        default: return "circle"
        }
    }

    /// Optimistically toggle the pin, persist, and revert on failure.
    private func togglePin(_ quote: QuoteSummary) async {
        guard let index = quotes.firstIndex(where: { $0.id == quote.id }) else { return }
        let newValue = !quote.pinned
        // Fire with the optimistic update so the tap feels instant, not
        // gated on the round trip.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // A spring rather than the default curve. Three things move at once —
        // the pin appears, the tint comes up, and the card travels to the
        // Pinned section — and a little overshoot makes that read as the card
        // answering rather than as a list quietly re-sorting itself.
        withAnimation(Self.pinSpring) { quotes[index].pinned = newValue }
        do {
            try await QuoteService.setPinned(id: quote.id, pinned: newValue)
        } catch {
            withAnimation(Self.pinSpring) { quotes[index].pinned = quote.pinned }
        }
    }

    private func changeStatus(_ quote: QuoteSummary, to newStatus: String) async {
        guard newStatus != quote.status,
              let index = quotes.firstIndex(where: { $0.id == quote.id }) else { return }
        let previous = quote.status
        withAnimation { quotes[index].status = newStatus }
        do {
            try await QuoteService.updateStatus(id: quote.id, status: newStatus)
            if newStatus == "sent" || newStatus == "viewed" {
                await QuoteExpiryNotifications.schedule(id: quote.id,
                                                        title: quote.displayTitle,
                                                        status: newStatus,
                                                        validityDate: quote.validityDate)
            } else {
                QuoteExpiryNotifications.cancel(quote)
            }
            // The user just won the job — make it land physically.
            if newStatus == "accepted" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            withAnimation { quotes[index].status = previous }
        }
    }

    private func duplicate(_ quote: QuoteSummary) async {
        // A copy is a new quote — the ledger has always counted it as one — so
        // it has to be asked for on the same terms as a recording. Counting it
        // without gating it was the worst of both: the allowance drained
        // without the user ever being told why.
        guard store.canCreateQuote(remaining: session.freeQuotesRemaining) else {
            store.isPaywallPresented = true
            return
        }
        do {
            try await QuoteService.duplicateQuote(id: quote.id)
            await load()
            // A copy is a new quote, and the ledger counts it as one.
            await session.refreshQuoteUsage()
            // The copy lands wherever the sort puts it, which on a long list is
            // out of sight. Without a word, confirming the alert looked like it
            // had done nothing — and the obvious response to that is to tap it
            // again and end up with three.
            toast = Toast(style: .success, message: "Copy saved as a draft")
        } catch let error where error.isQuoteAllowanceExhausted {
            await store.refreshEntitlement(forceReport: true)
            guard SubscriptionFlow.quotaRefusalOutcome(isPro: store.isPro) == .retryAfterEntitlementSync else {
                await session.refreshQuoteUsage()
                store.isPaywallPresented = true
                return
            }
            do {
                try await QuoteService.duplicateQuote(id: quote.id)
                await load()
                await session.refreshQuoteUsage()
                toast = Toast(style: .success, message: "Copy saved as a draft")
            } catch let retryError where retryError.isQuoteAllowanceExhausted {
                await session.refreshQuoteUsage()
                toast = Toast(style: .error, message: "Your subscription is still syncing. Try again in a moment.")
            } catch {
                toast = Toast(style: .error, message: "Couldn't duplicate this quote")
            }
        } catch {
            // Leave the list unchanged if the copy failed, but say so — the
            // silence read as success.
            toast = Toast(style: .error, message: "Couldn't duplicate this quote")
        }
    }
}

private extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}
