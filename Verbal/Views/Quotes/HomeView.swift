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
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.openURL) private var openURL
    @Binding var showCreate: Bool
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
    /// Visits booked but not quoted yet, soonest first. Held on the device —
    /// see `ScheduledVisit`.
    @State private var visits: [ScheduledVisit] = []
    /// Non-nil while the booking sheet is up, carrying what it opened on.
    @State private var visitEditor: VisitEditor?
    /// Held while the user confirms removing a booked visit.
    @State private var visitToDelete: ScheduledVisit?
    /// The visit whose action sheet is open.
    @State private var selectedVisit: ScheduledVisit?
    /// A booked visit that opened the recorder, so the saved quote can mark it done.
    @State private var visitForRecording: ScheduledVisit?
    /// A red visit that has been sitting for 24h and needs a decision.
    @State private var missedVisitPrompt: ScheduledVisit?
    /// The upcoming list shows the next few and hides the rest, so a busy week
    /// doesn't push the quotes off the screen. Set once the user asks for them.
    @State private var showsAllVisits = false

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

    /// How many visits are listed before the rest are folded away.
    private static let visitPreviewCount = 3

    var body: some View {
        NavigationStack(path: $path) {
            homeContent
            .background(Color(.homeBackground))
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
                // Search on its own, on the right. It is the one control that
                // changes what the list contains rather than where you are
                // going, and the field it opens drops from this side.
                //
                // Ours rather than the system's search item: that one brings
                // its own container wherever it is placed and cannot be pulled
                // into a group. The cost is that the magnifier drives
                // `isSearching` by hand; the field itself is still
                // `.searchable`, so the keyboard, cancel and dismissal
                // behaviour are unchanged.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search quotes")
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
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease"
                              : "line.3.horizontal.decrease.circle.fill")
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
            }
            .navigationDestination(isPresented: $showRateCard) {
                RateCardView()
            }
            // Continue pushes once the sheet is gone, rather than sliding a
            // screen in underneath it.
            .sheet(isPresented: $showRateCardIntro) {
                RateCardIntroSheet {
                    seenRateCardIntro = true
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))
                        showRateCard = true
                    }
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
            .task {
                // Seed instantly from the data preloaded during the splash so
                // the list appears with no empty-state flash, then refresh.
                if !hasLoaded {
                    quotes = session.quotes
                    hasLoaded = session.listsLoaded
                }
                // Read here rather than at init: `ScheduledVisit.load()` drops
                // the days that have already been and gone, and a phone left
                // open overnight would otherwise still be offering yesterday.
                visits = ScheduledVisit.load()
                promptForMissedVisitIfNeeded()
                await load()
            }
            .modifier(SessionSync(quotes: session.quotes,
                                  listsLoaded: session.listsLoaded,
                                  apply: sync))
            .onChange(of: quotes.isEmpty) { _, isEmpty in
                if !isEmpty { hasEverHadQuotes = true }
            }
            .onChange(of: visits) { _, _ in
                promptForMissedVisitIfNeeded()
            }
            .refreshable { await load() }
            .alert("Delete this quote?", isPresented: Binding(
                get: { quoteToDelete != nil },
                set: { if !$0 { quoteToDelete = nil } }
            ), presenting: quoteToDelete) { quote in
                Button("Delete", role: .destructive) {
                    Task { await delete(quote) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { quote in
                Text("This permanently deletes “\(quote.displayTitle)”. This can't be undone.")
            }
            .alert("Duplicate this quote?", isPresented: Binding(
                get: { quoteToDuplicate != nil },
                set: { if !$0 { quoteToDuplicate = nil } }
            ), presenting: quoteToDuplicate) { quote in
                Button("Duplicate") {
                    Task { await duplicate(quote) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { quote in
                Text("This creates a copy of “\(quote.displayTitle)” as a new draft.")
            }
            .modifier(VisitDeleteConfirmation(visit: $visitToDelete, onDelete: remove))
            .modifier(MissedVisitConfirmation(visit: $missedVisitPrompt,
                                               onRecord: { visit in
                markPromptedAndClear(visit)
                beginRecording(for: visit)
            },
                                               onDidNotHappen: markPromptedAndClear))
            .toast($toast)
        }
        // Presented from outside the NavigationStack: attaching this sheet to
        // the content inside the stack (which also owns a minimizing
        // .searchable toolbar) corrupts the navigation bar after dismissal —
        // broken title layout and lost push transitions on the next push.
        // The allowance is refreshed by the recording itself, once its insert
        // has actually landed. Doing it here raced that insert: closing the
        // sheet does not wait for banking to finish.
        .sheet(isPresented: $showCreate, onDismiss: {
            visitForRecording = nil
            Task { await load() }
        }) {
            let recordingVisit = visitForRecording
            QuoteRecordingView(scheduledVisit: recordingVisit) { quoteId in
                if let recordingVisit {
                    markRecorded(recordingVisit, quoteId: quoteId)
                }
            }
                .environment(session)
        }
        .sheet(item: $selectedVisit) { visit in
            let currentVisit = live(visit)
            VisitActionSheet(
                visit: currentVisit,
                action: visitAction(for: currentVisit),
                onPrimary: { performPrimaryVisitAction(currentVisit) },
                onDirections: { openDirections(for: currentVisit) },
                onCall: { toast = Toast(style: .error, message: "No phone number saved") },
                onReschedule: { visitEditor = .existing(currentVisit) },
                onCancel: { visitToDelete = currentVisit },
                onDidNotHappen: { markPromptedAndClear(currentVisit) },
                onOpenQuote: { openRecordedQuote(for: currentVisit) }
            )
        }
        // Outside the stack for the same reason the recorder is: a sheet
        // attached inside it, alongside the minimizing `.searchable` toolbar,
        // leaves the navigation bar broken once it closes.
        .sheet(item: $visitEditor) { editor in
            switch editor {
            case .new:
                ScheduleVisitSheet(onSave: addOrUpdate)
            case .existing(let visit):
                ScheduleVisitSheet(editing: visit,
                                   onSave: addOrUpdate,
                                   onDelete: remove)
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
        } else if quotes.isEmpty && visits.isEmpty {
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

                upcomingSection

                ForEach(sections, id: \.title) { section in
                    // Header as a normal row (not a Section header) so it scrolls
                    // away with the content instead of pinning to the top.
                    Text(section.title)
                        // A shade heavier than the body around it. Not darker as
                        // well: a date carries less than a status heading did, and
                        // it only has to mark where one day ends and the next
                        // begins.
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 20))

                    ForEach(section.quotes) { quote in
                        ZStack {
                            QuoteRow(quote: quote,
                                     unpricedCount: unpricedCount(for: quote))
                            // Zero-opacity link so the row navigates without the
                            // default trailing chevron. By value rather than by
                            // closure: this row is rebuilt whenever the session's
                            // copy of the quote changes, and a closure link left
                            // the screen it pushed detached from the list feeding
                            // it — see the destination below.
                            NavigationLink(value: quote) { EmptyView() }
                                .opacity(0)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                        .onAppear {
                            // Warm the cache so tapping opens the detail with line
                            // items already on screen.
                            Task { await session.prefetchLineItems(for: quote.id) }
                        }
                        .contextMenu { quoteMenu(for: quote) }
                        // The two moves the list is actually read for: chase the
                        // ones that have gone quiet, tick off the ones that came
                        // back yes. Both were buried in a long-press menu, which
                        // is where features go to be forgotten.
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            // "Nudge" is the share panel again — sending the
                            // quote a second time is what a nudge is here, and
                            // inventing a separate reminder would be a feature,
                            // not a swipe.
                            Button {
                                share(quote)
                            } label: {
                                Label("Nudge", systemImage: "bell.fill")
                            }
                            .tint(Color(.royalBlue300))

                            Button {
                                Task { await changeStatus(quote, to: "accepted") }
                            } label: {
                                Label("Accepted", systemImage: "checkmark.circle.fill")
                            }
                            .tint(Color(.statusAcceptedText))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // No .destructive role: it would animate the row out
                            // on tap, before the confirmation alert is answered.
                            Button {
                                quoteToDelete = quote
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)

                            Button {
                                share(quote)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(Color(.royalBlue300))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Room under the last row for the floating tab bar, which draws
            // over the list rather than beside it. Without this the bottom
            // quote is permanently cut in half, and the one below it is the one
            // you can never quite reach.
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

    // MARK: - Upcoming

    /// Visits booked in but not quoted yet, sitting above the quotes themselves.
    ///
    /// This is where the month calendar used to be. That one counted what had
    /// already happened — quotes made this month, a dot under each day one
    /// landed — which is exactly what the list underneath was already showing,
    /// row by row and in more detail. The top of this screen is worth more
    /// pointed the other way: the next job to walk into is the thing that isn't
    /// written down anywhere else in the app, and every line here is one tap
    /// from the recorder that turns it into a quote.
    ///
    /// A `Group` of plain rows rather than one packed card, so each visit is a
    /// real list row with its own swipe actions — the same way the day headings
    /// below are rows rather than pinned section headers.
    @ViewBuilder
    private var upcomingSection: some View {
        upcomingHeader

        if visits.isEmpty {
            upcomingEmpty
        } else {
            upcomingVisitsCard
        }
    }

    /// The next few. A tradesperson with a full fortnight booked shouldn't have
    /// to scroll past all of it to reach the quote they came here for.
    private var shownVisits: [ScheduledVisit] {
        showsAllVisits ? visits : Array(visits.prefix(Self.visitPreviewCount))
    }

    /// Same weight and colour as the day headings below, because it is the same
    /// kind of thing: a heading over a run of rows, scrolling away with them.
    private var upcomingHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Upcoming")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            // Only once there is a list to add to. Empty, the card below is
            // already offering this in its own words, and two invitations to
            // do one thing read as two different things.
            if !visits.isEmpty {
                Button {
                    visitEditor = .new
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                        Text("Book a visit")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Color(.blueAccentText))
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }

    private var upcomingVisitsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(visitGroups.enumerated()), id: \.element.day) { groupIndex, group in
                if groupIndex > 0 { Divider().padding(.vertical, 4) }

                VStack(alignment: .leading, spacing: 6) {
                    Text(dayHeaderText(for: group.day))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .padding(.top, groupIndex == 0 ? 12 : 6)

                    ForEach(group.visits) { visit in
                        compactVisitRow(visit, isNext: visit.id == shownVisits.first?.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if visits.count > Self.visitPreviewCount {
                Divider().padding(.top, 6)
                Button {
                    withAnimation(Self.visitExpansionAnimation) { showsAllVisits.toggle() }
                } label: {
                    Text(showsAllVisits
                         ? "Show fewer"
                         : "\(visits.count - Self.visitPreviewCount) more booked in")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color(.blueAccentText))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
        .animation(Self.visitExpansionAnimation, value: showsAllVisits)
    }

    private var visitGroups: [(day: Date, visits: [ScheduledVisit])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: shownVisits) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            (day: day, visits: grouped[day, default: []].sorted { $0.date < $1.date })
        }
    }

    private func dayHeaderText(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }

        let weekday = day.formatted(.dateTime.weekday(.wide))
        let monthDay = day.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday), \(monthDay)"
    }

    private func compactVisitRow(_ visit: ScheduledVisit, isNext: Bool) -> some View {
        let statusColor = visitStatusColor(for: visit)
        let rowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return Button {
            selectedVisit = visit
        } label: {
            HStack(spacing: 10) {
                Capsule()
                    .fill(statusColor)
                    .frame(width: 3, height: 24)

                Text(visit.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)

                Spacer(minLength: 10)

                Text(visit.date.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isNext ? statusColor.opacity(0.08) : Color.clear, in: rowShape)
            .contentShape(.interaction, rowShape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(visit.accessibilityText)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private func visitStatusColor(for visit: ScheduledVisit) -> Color {
        if hasRecordedQuote(for: visit) { return Color(.statusAcceptedText) }
        if Date() >= visit.date.addingTimeInterval(2 * 60 * 60) { return Color(.statusDeclinedText) }
        return Color(.statusWarningText)
    }

    private func hasRecordedQuote(for visit: ScheduledVisit) -> Bool {
        if visit.recordedQuoteId != nil { return true }
        let visitTitle = visit.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !visitTitle.isEmpty else { return false }
        return quotes.contains { quote in
            Calendar.current.isDate(quote.createdAt, inSameDayAs: visit.date)
                && (quote.displayTitle.lowercased() == visitTitle
                    || quote.clientName?.lowercased() == visitTitle)
        }
    }

    /// One booked visit, drawn as the quote rows are drawn: the list has one
    /// row language, and a visit is a quote that hasn't been spoken yet.
    private func visitRow(_ visit: ScheduledVisit) -> some View {
        Button {
            // The whole point of the row. Tapping opens the recorder, which is
            // the one thing this visit exists to lead to.
            showCreate = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(visit.title)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)

                    // Today's visit is the only one that changes what the user
                    // does next, so it is the only one that takes the accent.
                    Text(visit.whenText)
                        .font(.subheadline)
                        .foregroundStyle(visit.isToday ? Color(.blueAccentText) : Color.secondary)

                    if let note = visit.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 0)

                // `royalBlue25` is the tint this app puts on things asking to
                // be tapped, and the mic says which tap it is — this row does
                // not open a screen, it starts a recording.
                Image(systemName: "mic.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.blueAccentText))
                    .frame(width: 36, height: 36)
                    .background(Color(.royalBlue25), in: Circle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            // Tall enough for iOS to draw the swipe actions as icon-above-label,
            // matching the quote rows below — see the same frame on `QuoteRow`.
            .frame(minHeight: 78)
            .background(Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(visit.accessibilityText). Record a quote")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
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

    private var moreVisitsButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { showsAllVisits.toggle() }
        } label: {
            Text(showsAllVisits
                 ? "Show fewer"
                 : "\(visits.count - Self.visitPreviewCount) more booked in")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(.blueAccentText))
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 24, bottom: 6, trailing: 20))
    }

    /// Nothing booked in. The same sentence the rate card says when it has been
    /// emptied, in the same component so the two can't drift into two dialects
    /// — set on a card the size of the row it is standing in for, because here
    /// it is one empty section rather than an empty screen.
    private var upcomingEmpty: some View {
        EmptyStateMessage(
            icon: "calendar",
            title: "Nothing booked in",
            message: "Put the visits you've got coming up here and each one is a tap from a quote."
        ) {
            EmptyStatePill(title: "Book a visit", icon: "plus") { visitEditor = .new }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
    }

    /// New booking, or a correction to one. Sorted on the way in so the list
    /// and the stored copy are always in the order they're read in.
    private func addOrUpdate(_ visit: ScheduledVisit) {
        withAnimation(Self.rowInsert) {
            if let index = visits.firstIndex(where: { $0.id == visit.id }) {
                visits[index] = visit
            } else {
                visits.append(visit)
            }
            visits.sort { $0.date < $1.date }
        }
        ScheduledVisit.save(visits)
        Task { await ScheduledVisitNotifications.schedule(visit) }
    }

    private func remove(_ visit: ScheduledVisit) {
        withAnimation(Self.rowRemoval) {
            visits.removeAll { $0.id == visit.id }
            if visits.count <= Self.visitPreviewCount { showsAllVisits = false }
        }
        ScheduledVisit.save(visits)
        ScheduledVisitNotifications.cancel(visit)
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

        let visitTitle = visit.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !visitTitle.isEmpty else { return nil }
        return quotes.first { quote in
            Calendar.current.isDate(quote.createdAt, inSameDayAs: visit.date)
                && (quote.displayTitle.lowercased() == visitTitle
                    || quote.clientName?.lowercased() == visitTitle)
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
            visitForRecording = visit
            showCreate = true
        }
    }

    private func markRecorded(_ visit: ScheduledVisit, quoteId: UUID) {
        guard let index = visits.firstIndex(where: { $0.id == visit.id }) else { return }
        visits[index].recordedQuoteId = quoteId
        visits[index].didPromptForMissedVisit = false
        ScheduledVisit.save(visits)
        ScheduledVisitNotifications.cancel(visits[index])
        Task { await load() }
    }

    private func markPromptedAndClear(_ visit: ScheduledVisit) {
        missedVisitPrompt = nil
        var cleared = visit
        cleared.didPromptForMissedVisit = true
        ScheduledVisitNotifications.cancel(cleared)
        withAnimation(Self.rowRemoval) {
            visits.removeAll { $0.id == visit.id }
            if visits.count <= Self.visitPreviewCount { showsAllVisits = false }
        }
        ScheduledVisit.save(visits)
    }

    private func promptForMissedVisitIfNeeded() {
        guard missedVisitPrompt == nil else { return }
        missedVisitPrompt = visits.first { visit in
            !hasRecordedQuote(for: visit)
                && !visit.didPromptForMissedVisit
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
            Label("Delete", systemImage: "trash")
        }
    }

    /// First run: an invitation into the core loop, not a note that the list
    /// is empty. This is the screen a new user meets straight after onboarding.
    /// No button of its own — the mic in the tab bar is the way in, and a second
    /// control for the same thing only splits the attention it needs.
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
            // The action is a quiet pill rather than the blue Record button. The
            // mic is already in the tab bar an inch below it, so the solid
            // version was the same offer made twice on a screen whose whole
            // point is that there is nothing to look at.
            EmptyStateMessage(
                icon: "waveform",
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
                Image(systemName: "mic.fill")
                Text("Record a quote").fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .background(Color(.royalBlue600), in: Capsule())
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
        VStack(spacing: 10) {
            ForEach(Array(Self.skeletonWidths.enumerated()), id: \.offset) { _, width in
                QuoteRowSkeleton(titleWidth: width)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        // One sweep travelling across the whole stack, not four in step.
        .shimmer(active: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your quotes")
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

    /// The upcoming card grows inside another list row. A softer spring lets the
    /// added visits settle without making the card feel like it jumped taller.
    private static let visitExpansionAnimation = Animation.spring(response: 0.42, dampingFraction: 0.86)

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

    /// The list, split into Pinned and then one section per day.
    ///
    /// The headings stay absolute ("Wed 12 Aug") now that the rows have gone
    /// relative. That is the division of labour: the heading says which day you
    /// are looking at, the row says how long ago that was.
    private var sections: [(title: String, quotes: [QuoteSummary])] {
        let query = searchQuery.lowercased()
        let filtered = quotes.filter { quote in
            guard filter.matches(quote.effectiveStatus) else { return false }
            guard !query.isEmpty else { return true }
            return quote.displayTitle.lowercased().contains(query)
                || (quote.jobSummary?.lowercased().contains(query) ?? false)
        }
        // Pinned quotes get their own section at the very top and are excluded
        // from the date sections below so they aren't listed twice.
        let pinned = filtered.filter(\.pinned)
        let rest = filtered.filter { !$0.pinned }

        // By day, not by status. Every row already wears a status pill, so a
        // status heading was saying the same thing twice — and status is a
        // filter, which is the toolbar's job. Grouped by date the list reads
        // the way people look for a quote: the one from Tuesday.
        let calendar = Calendar.current
        var days: [Date: [QuoteSummary]] = [:]
        for quote in rest {
            days[calendar.startOfDay(for: quote.createdAt), default: []].append(quote)
        }

        var result: [(title: String, quotes: [QuoteSummary])] = []
        if !pinned.isEmpty {
            result.append(("Pinned", pinned))
        }
        // Newest day first. Within a day the server's ordering already holds —
        // it returns created_at descending — so the rows keep the order they
        // were fetched in.
        result += days.keys.sorted(by: >).map { day in
            (quoteSectionTitle(day), days[day] ?? [])
        }
        return result
    }

    // MARK: - Data

    /// Load the line items (usually already prefetched by the row) before
    /// opening the share panel — without them the PDF would print an empty
    /// table, so this waits rather than rendering a half-built document.
    private func share(_ quote: QuoteSummary) {
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
        if (quote.clientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shareAfterNoClient = quote
        } else {
            shareTarget = quote
        }
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
            business: session.businessProfile,
            logo: session.businessLogo
        )
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
            // Also drop it from the shared list, so the Clients tab (drawn from
            // it) loses the quote too, not just this screen's own copy.
            session.removeQuote(id: quote.id)
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
            // The user just won the job — make it land physically.
            if newStatus == "accepted" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            withAnimation { quotes[index].status = previous }
        }
    }

    private func duplicate(_ quote: QuoteSummary) async {
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
        } catch {
            // Leave the list unchanged if the copy failed, but say so — the
            // silence read as success.
            toast = Toast(style: .error, message: "Couldn't duplicate this quote")
        }
    }
}

// MARK: - Visit Actions

private enum VisitAction {
    case future, happeningNow, passed, recorded(QuoteSummary?)
}

private struct VisitActionSheet: View {
    let visit: ScheduledVisit
    let action: VisitAction
    let onPrimary: () -> Void
    let onDirections: () -> Void
    let onCall: () -> Void
    let onReschedule: () -> Void
    let onCancel: () -> Void
    let onDidNotHappen: () -> Void
    let onOpenQuote: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(visit.title)
                        .font(.robotoSlab(24, relativeTo: .title3))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(2)

                    Text(visit.date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "Address", value: visit.address)
                    detailRow(label: "Note", value: visit.note)
                }

                Spacer(minLength: 0)

                actionButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .navigationTitle("Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(.systemBackground))
    }

    @ViewBuilder
    private var actionButtons: some View {
        if case .passed = action {
            VStack(spacing: 10) {
                secondaryButton("Reschedule", action: onReschedule)
                borderedDestructiveButton("Didn't happen", action: onDidNotHappen)
                primaryButton
            }
        } else {
            VStack(spacing: 10) {
                primaryButton
                secondaryActions
            }
        }
    }

    private var primaryButton: some View {
        Group {
            if case .future = action {
                borderedBlueButton(primaryTitle, action: onPrimary)
            } else {
                Button {
                    closeThen(onPrimary)
                } label: {
                    Text(primaryTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(.royalBlue600),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        switch action {
        case .future:
            secondaryButton("Call client", action: onCall)
            secondaryButton("Reschedule", action: onReschedule)
            borderedDestructiveButton("Cancel", action: onCancel)
        case .happeningNow:
            borderedBlueButton("Directions", action: onDirections)
            secondaryButton("Call client", action: onCall)
        case .passed:
            EmptyView()
        case .recorded:
            EmptyView()
        }
    }

    private var primaryTitle: String {
        switch action {
        case .future: return "Directions"
        case .happeningNow: return "Start recording"
        case .passed: return "Record now"
        case .recorded: return "Open quote"
        }
    }

    private func detailRow(label: String, value: String?) -> some View {
        let cleanValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(cleanValue.isEmpty ? "Not added" : cleanValue)
                .font(.subheadline)
                .foregroundStyle(cleanValue.isEmpty ? .secondary : Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secondaryButton(_ title: String,
                                 role: ButtonRole? = nil,
                                 action: @escaping () -> Void) -> some View {
        Button(role: role) {
            closeThen(action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color(.statusDeclinedText) : Color(.blueAccentText))
    }

    private func borderedDestructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            closeThen(action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.statusDeclinedText))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.statusDeclinedFill),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.statusDeclinedText).opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func borderedBlueButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            closeThen(action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.blueAccentText))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.royalBlue25),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.blueAccentText).opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func closeThen(_ action: @escaping () -> Void) {
        dismiss()
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            await MainActor.run { action() }
        }
    }
}

// MARK: - Visit Deletion

private struct VisitDeleteConfirmation: ViewModifier {
    @Binding var visit: ScheduledVisit?
    let onDelete: (ScheduledVisit) -> Void

    func body(content: Content) -> some View {
        content.alert("Delete upcoming quote?", isPresented: Binding(
            get: { visit != nil },
            set: { if !$0 { visit = nil } }
        ), presenting: visit) { visit in
            Button("Delete", role: .destructive) {
                onDelete(visit)
                self.visit = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { visit in
            Text("This removes “\(visit.title)” from Upcoming. This can't be undone.")
        }
    }
}

private struct MissedVisitConfirmation: ViewModifier {
    @Binding var visit: ScheduledVisit?
    let onRecord: (ScheduledVisit) -> Void
    let onDidNotHappen: (ScheduledVisit) -> Void

    func body(content: Content) -> some View {
        content.alert("Did this visit happen?", isPresented: Binding(
            get: { visit != nil },
            set: { if !$0 { visit = nil } }
        ), presenting: visit) { visit in
            Button("Record it") {
                onRecord(visit)
                self.visit = nil
            }
            Button("Didn't happen", role: .destructive) {
                onDidNotHappen(visit)
                self.visit = nil
            }
        } message: { visit in
            Text("“\(visit.title)” is still on your upcoming list.")
        }
    }
}

// MARK: - Search

/// Adds `.searchable` only once search has been asked for, and takes it away
/// again when it's dismissed.
///
/// `.searchable` with an `isPresented` binding still reserves the field's place
/// in the navigation bar while it's closed, which is a search bar sitting on a
/// screen nobody asked to search. Attaching the modifier itself conditionally
/// is what actually leaves the screen alone until the magnifier is tapped.
struct SearchWhenAsked: ViewModifier {
    let isActive: Bool
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String

    func body(content: Content) -> some View {
        if isActive {
            content.searchable(text: $text, isPresented: $isPresented, prompt: prompt)
        } else {
            content
        }
    }
}

// MARK: - Filtering

/// Watches the session's copy of the quote list on Home's behalf.
///
/// A modifier rather than two `onChange`s in the body: that body is already at
/// the limit of what the type-checker will take in one expression, and the
/// second one tipped it over.
private struct SessionSync: ViewModifier {
    let quotes: [QuoteSummary]
    let listsLoaded: Bool
    let apply: ([QuoteSummary], Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: quotes) { _, fresh in apply(fresh, listsLoaded) }
            .onChange(of: listsLoaded) { _, loaded in apply(quotes, loaded) }
    }
}
