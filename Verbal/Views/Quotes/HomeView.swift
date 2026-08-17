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
    @Binding var showCreate: Bool
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

    var body: some View {
        NavigationStack {
            Group {
                if quotes.isEmpty && !hasLoaded {
                    // Still loading first paint — placeholders, not "no quotes".
                    loadingState
                } else if quotes.isEmpty && loadFailed {
                    // Don't claim the account is empty when the fetch failed.
                    errorState
                } else if quotes.isEmpty {
                    emptyState
                } else if sections.isEmpty {
                    // Quotes exist, but the search or filter excluded them all.
                    noMatchesState
                } else {
                    quotesList
                }
            }
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
                await load()
            }
            // Bootstrap can finish after this view has already read an empty
            // list — signing in reaches Home before the preload returns. Take
            // what arrives rather than sitting on the empty copy.
            .onChange(of: session.listsLoaded) { _, loaded in
                guard loaded, quotes.isEmpty, !session.quotes.isEmpty else { return }
                quotes = session.quotes
                loadFailed = false
            }
            .onChange(of: quotes.isEmpty) { _, isEmpty in
                if !isEmpty { hasEverHadQuotes = true }
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
            .toast($toast)
        }
        // Presented from outside the NavigationStack: attaching this sheet to
        // the content inside the stack (which also owns a minimizing
        // .searchable toolbar) corrupts the navigation bar after dismissal —
        // broken title layout and lost push transitions on the next push.
        // The allowance is refreshed by the recording itself, once its insert
        // has actually landed. Doing it here raced that insert: closing the
        // sheet does not wait for banking to finish.
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
            QuoteRecordingView()
                .environment(session)
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
                                     unpricedCount: unpricedCount(for: quote),
                                     dayIsKnown: section.dated)
                            // Zero-opacity link so the row navigates without the
                            // default trailing chevron.
                            NavigationLink {
                                QuoteDetailView(
                                    quote: quote,
                                    initialLineItems: session.lineItems(for: quote.id) ?? [],
                                    onDeleted: {
                                        withAnimation(Self.rowRemoval) {
                                            quotes.removeAll { $0.id == quote.id }
                                        }
                                        // Delay so the toast animates in on the
                                        // now-visible Home, after the detail view's
                                        // pop finishes (setting it mid-dismiss shows
                                        // it off-screen and it's effectively missed).
                                        Task {
                                            try? await Task.sleep(for: .seconds(0.4))
                                            toast = Toast(style: .success, message: "Quote deleted")
                                        }
                                    },
                                    onRenamed: { newTitle in
                                        // This list holds its own copy of the rows
                                        // and only refetches on its own schedule,
                                        // so the row keeps the old name until told.
                                        guard let index = quotes.firstIndex(where: { $0.id == quote.id })
                                        else { return }
                                        quotes[index].title = newTitle
                                    },
                                    onPinChanged: { isPinned in
                                        guard let index = quotes.firstIndex(where: { $0.id == quote.id })
                                        else { return }
                                        // The same spring the row's own pin uses, so
                                        // popping back finds the card already where
                                        // it belongs rather than watching it jump.
                                        withAnimation(Self.pinSpring) {
                                            quotes[index].pinned = isPinned
                                        }
                                    },
                                    onNeedsRefresh: { Task { await load() } }
                                )
                                .environment(session)
                            } label: { EmptyView() }
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

    /// `dated` says the heading above these rows names a day, so the rows can
    /// drop to a clock time. False for Pinned, which spans every day there is.
    private var sections: [(title: String, dated: Bool, quotes: [QuoteSummary])] {
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

        var result: [(title: String, dated: Bool, quotes: [QuoteSummary])] = []
        if !pinned.isEmpty {
            result.append(("Pinned", false, pinned))
        }
        // Newest day first. Within a day the server's ordering already holds —
        // it returns created_at descending — so the rows keep the order they
        // were fetched in.
        result += days.keys.sorted(by: >).map { day in
            (quoteSectionTitle(day), true, days[day] ?? [])
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

/// Filter options for the toolbar menu.
enum QuoteFilter: CaseIterable, Hashable, Identifiable {
    case all, drafts, waiting, accepted, declined, expired

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "All"
        case .drafts: return "Drafts"
        case .waiting: return "Waiting to hear back"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .expired: return "Expired"
        }
    }

    private var statuses: Set<String>? {
        switch self {
        case .all: return nil
        case .drafts: return ["draft"]
        case .waiting: return ["sent", "viewed"]
        case .accepted: return ["accepted"]
        case .declined: return ["declined"]
        case .expired: return ["expired"]
        }
    }

    func matches(_ status: String) -> Bool {
        statuses?.contains(status) ?? true
    }
}
