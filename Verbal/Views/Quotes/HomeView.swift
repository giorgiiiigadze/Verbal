//
//  HomeView.swift
//  Verbal
//
//  The "Your quotes" tab: a searchable, filterable, status-grouped list of the
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
    @State private var toast: Toast?
    /// True when the last fetch failed — distinguishes "no quotes" from
    /// "couldn't reach the server".
    @State private var loadFailed = false
    /// Outstanding quotes converted into the user's currency. Nil until the
    /// first calculation finishes.
    @State private var outstandingTotal: Double?
    /// Quotes actually included above — a pair with no available rate is left
    /// out rather than silently added at the wrong value.
    @State private var outstandingCount = 0
    /// True when at least one quote needed converting, so the figure is
    /// a daily-rate approximation rather than an exact sum.
    @State private var outstandingIsApproximate = false
    /// Observed so the summary re-converts when the user changes currency.
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
            .navigationTitle("Your quotes")
            // Fixed in the bar, matching the rate card. Two tabs that behave
            // differently under the same thumb read as two apps — and the large
            // title was giving its height to a name the tab bar is already
            // showing, on the screen with the most to list.
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
                ToolbarItem(placement: .topBarLeading) {
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
                }
                // The rate card, which used to be a tab of its own. It is setup
                // rather than a place — filled in once and topped up now and
                // then, mostly from the prompt after a recording — so it was
                // spending a permanent slot on a monthly visit.
                //
                // One group, so the bar gives the pair a single glass container:
                // the rate card and search are both "leave this list", and two
                // separate circles made them look like two unrelated controls.
                //
                // Both buttons are ours because the system's search item cannot
                // be pulled into a group with a custom one — it brings its own
                // container wherever it is placed. The cost is that the
                // magnifier drives `isSearching` by hand instead of the system
                // doing it; the search field itself is still `.searchable`, so
                // the keyboard, cancel and dismissal behaviour are unchanged.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        RateCardView()
                    } label: {
                        Image(systemName: "rectangle.stack")
                    }
                    .accessibilityLabel("Rate card")

                    Button {
                        isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search quotes")
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
            .task(id: outstandingSignature) { await recalculateOutstanding() }
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

    private var quotesList: some View {
        List {
            // Money in play, above the list — the number worth opening the app
            // for. Hidden while searching or filtering, when it'd be misleading.
            // Stays up under the waiting filter, where it describes exactly the
            // set on screen — and is the way back out of it.
            if outstandingTotal != nil, outstandingCount > 0, searchQuery.isEmpty,
               filter == .all || filter == .waiting {
                Button {
                    // The band names a specific set of quotes, so touching it
                    // shows them. Same filter the toolbar menu offers, put where
                    // the eye already is.
                    withAnimation { filter = filter == .waiting ? .all : .waiting }
                } label: {
                    outstandingSummary
                }
                    .buttonStyle(BandPressStyle())
                    // Full-bleed tinted band rather than a floating card, so the
                    // top of the screen reads as its own header zone.
                    .listRowBackground(
                        Color(.royalBlue25)
                            .overlay(alignment: .bottom) {
                                // Hairline where the band meets the page.
                                Rectangle()
                                    .fill(Color(.separator))
                                    .frame(height: 0.5)
                            }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
            }

            ForEach(sections, id: \.title) { section in
                // Header as a normal row (not a Section header) so it scrolls
                // away with the content instead of pinning to the top.
                Text(section.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 2, trailing: 20))

                ForEach(section.quotes) { quote in
                    ZStack {
                        QuoteRow(quote: quote, unpricedCount: unpricedCount(for: quote))
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
    }

    /// Quotes with a client and no decision yet — the pipeline.
    private var outstanding: [QuoteSummary] {
        quotes.filter { $0.effectiveStatus == "sent" || $0.effectiveStatus == "viewed" }
    }

    private var outstandingLabel: String {
        guard let outstandingTotal else { return "—" }
        let formatted = AppCurrency.format(outstandingTotal, code: currencyCode)
        return outstandingIsApproximate ? "≈ \(formatted)" : formatted
    }

    /// Convert each outstanding quote into the user's currency and total them.
    /// A pair with no published rate is excluded from both the sum and the
    /// count, so the figure is never quietly wrong.
    /// Changes whenever the figure would — the quotes in play, their amounts
    /// and currencies, or the currency they're being shown in.
    private var outstandingSignature: String {
        outstanding.map { "\($0.id)|\($0.total)|\($0.currency ?? "")" }
            .joined(separator: ",") + "→" + currencyCode
    }

    private func recalculateOutstanding() async {
        let target = currencyCode
        var sum = 0.0
        var counted = 0
        var converted = false

        for quote in outstanding {
            let code = quote.currency ?? target
            if code == target {
                sum += quote.total
                counted += 1
            } else if let rate = try? await FXService.rate(from: code, to: target) {
                sum += quote.total * rate
                counted += 1
                converted = true
            }
        }

        outstandingTotal = sum
        outstandingCount = counted
        outstandingIsApproximate = converted
    }

    /// Age of the oldest quote still waiting on a client.
    ///
    /// Read from `createdAt` because that's all a summary carries — there's no
    /// sent-at timestamp — so this says "oldest", not "sent", and doesn't claim
    /// to date something it can't see.
    private var oldestLabel: String? {
        guard let oldest = outstanding.map(\.createdAt).min() else { return nil }
        return "Oldest · \(oldest.formatted(.relative(presentation: .named)))"
    }

    private var outstandingSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Waiting on clients")
                    .font(.caption)
                    .foregroundStyle(Color(.blueAccentText))
                // Always in the user's own currency, converting quotes priced
                // in another one — a raw sum across currencies is meaningless.
                Text(outstandingLabel)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
                // The total on its own is a fact. The age is the part that says
                // whether anything needs chasing.
                if let oldestLabel {
                    Text(oldestLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("\(outstandingCount) quote\(outstandingCount == 1 ? "" : "s")")
                Image(systemName: filter == .waiting ? "chevron.left" : "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(Color(.blueAccentText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The band is mostly empty space, and all of it should be the target.
        .contentShape(.rect)
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

    /// Quotes grouped into status sections, honoring the active filter.
    /// Section titles include a count, e.g. "Waiting to hear back · 2".
    /// The trimmed search text, as typed (for display in the no-match state).
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sections: [(title: String, quotes: [QuoteSummary])] {
        let query = searchQuery.lowercased()
        let filtered = quotes.filter { quote in
            guard filter.matches(quote.effectiveStatus) else { return false }
            guard !query.isEmpty else { return true }
            return quote.displayTitle.lowercased().contains(query)
                || (quote.jobSummary?.lowercased().contains(query) ?? false)
        }
        // Pinned quotes get their own section at the very top and are excluded
        // from the status sections below so they aren't listed twice.
        let pinned = filtered.filter(\.pinned)
        let rest = filtered.filter { !$0.pinned }

        var groups: [QuoteStatusGroup: [QuoteSummary]] = [:]
        for quote in rest {
            groups[QuoteStatusGroup(status: quote.effectiveStatus), default: []].append(quote)
        }
        var result: [(title: String, quotes: [QuoteSummary])] = []
        if !pinned.isEmpty {
            result.append(("Pinned · \(pinned.count)", pinned))
        }
        result += QuoteStatusGroup.allCases.compactMap { group in
            guard let items = groups[group], !items.isEmpty else { return nil }
            return ("\(group.title) · \(items.count)", items)
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
            quotes = try await fetchAllowingOneRetry()
            loadFailed = false
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

// MARK: - Row

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

/// Internal rather than private: the clients tab lists a client's quotes and
/// they have to be the same row, or the app has two ways of drawing a quote and
/// they drift.
struct QuoteRow: View {
    let quote: QuoteSummary
    /// Lines this quote can't price yet. Passed in because the summary row
    /// doesn't know what's inside a quote — the list reads it from the prefetch.
    var unpricedCount: Int = 0

    /// Drafts only, and it takes the status pill's place rather than adding to
    /// the row.
    ///
    /// The list is already grouped under "Drafts · 5", so a pill repeating that
    /// word is the least informative thing in the row and can be spent on the
    /// exception instead. Once a quote has gone out the trade is off: the gap
    /// was sent deliberately as TBC, and what the customer has done with it
    /// since is the thing worth reading.
    private var showsUnpriced: Bool {
        unpricedCount > 0 && quote.effectiveStatus == "draft"
    }
    @Environment(\.colorScheme) private var scheme

    /// RoyalBlue600 has no dark variant — it is #192868 in both appearances —
    /// so on a pinned card, which is itself a dark blue in dark mode, the pin
    /// was navy on navy. White in the dark, the same inversion the sign-in
    /// waves needed for the same reason.
    private var pinColor: Color {
        scheme == .dark ? .white : Color(.royalBlue600)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if quote.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(pinColor)
                            // Springs in from nothing at the corner it will
                            // occupy, so the pin reads as being pressed into
                            // the card rather than fading onto it.
                            .transition(
                                .scale(scale: 0.1, anchor: .bottomLeading)
                                    .combined(with: .opacity)
                            )
                    }
                    Text(quote.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                }
                // Lead with the client when there is one — job titles repeat
                // ("Bathroom re-tiling" three times over), names don't.
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(AppCurrency.format(quote.total, code: quote.currency))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
                statusPill
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(quote.pinned ? Color(.royalBlue25) : Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Client name when known, otherwise when the quote was made. The client is
    /// the more useful identifier — several quotes share the same job title.
    private var subtitle: String {
        let age = quote.createdAt.formatted(.relative(presentation: .named))
        guard let client = quote.clientName, !client.isEmpty else { return age }
        return "\(client) · \(age)"
    }

    /// Small tinted capsule naming the quote's status — pale blue for the
    /// working states, green/red for the settled ones.
    ///
    /// "Viewed" is the exception, and deliberately: it's the one state that
    /// reports something the customer did rather than something the user did,
    /// and it's the moment worth acting on. Set like "Sent" — both were
    /// `blueAccentText` on near-identical pale blue — it said the quote had
    /// gone out, when what it actually says is that somebody is reading it.
    private var statusPill: some View {
        HStack(spacing: 4) {
            if quote.effectiveStatus == "viewed" {
                Image(systemName: "eye.fill")
                    .font(.caption2)
            }
            Text(showsUnpriced ? "\(unpricedCount) unpriced" : pillLabel)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(pillForeground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(pillBackground, in: Capsule())
    }

    private var pillLabel: String {
        switch quote.effectiveStatus {
        case "draft": return "Draft"
        case "sent": return "Sent"
        case "viewed": return "Viewed"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "expired": return "Expired"
        default: return quote.effectiveStatus.capitalized
        }
    }

    private var pillForeground: Color {
        if showsUnpriced { return LineItemRow.amber }
        switch quote.effectiveStatus {
        case "draft": return .orange
        case "viewed": return .white
        case "accepted": return .green
        case "declined": return .red
        case "expired": return .secondary
        default: return Color(.blueAccentText)
        }
    }

    private var pillBackground: Color {
        if showsUnpriced { return LineItemRow.amber.opacity(0.14) }
        switch quote.effectiveStatus {
        case "draft": return .orange.opacity(0.14)
        // Filled, where every other state is a tint. The only pill on the
        // screen that has to be seen from across the list.
        case "viewed": return Color(.royalBlue600)
        case "accepted": return .green.opacity(0.14)
        case "declined": return .red.opacity(0.12)
        case "expired": return Color(.separator).opacity(0.5)
        default: return Color(.royalBlue25)
        }
    }
}

// MARK: - Loading placeholder

/// A quote card with its content replaced by bars. Deliberately built to
/// `QuoteRow`'s geometry — same radius, padding, border and column positions —
/// so the real cards land where the placeholders were instead of shifting the
/// page as they arrive.
private struct QuoteRowSkeleton: View {
    let titleWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                bar(titleWidth, 15)
                bar(titleWidth * 0.55, 11)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                bar(62, 13)
                bar(52, 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private func bar(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
    }
}

// MARK: - Status grouping & filtering

/// Status buckets shown as list sections (in display order).
/// A full-bleed List row draws no highlight of its own, so without this a tap on
/// the summary band looks like nothing happened until the list rearranges.
private struct BandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum QuoteStatusGroup: CaseIterable, Hashable {
    case drafts, waiting, accepted, declined, expired, other

    init(status: String) {
        switch status {
        case "draft": self = .drafts
        case "sent", "viewed": self = .waiting
        case "accepted": self = .accepted
        case "declined": self = .declined
        case "expired": self = .expired
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .drafts: return "Drafts"
        case .waiting: return "Waiting to hear back"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .expired: return "Expired"
        case .other: return "Other"
        }
    }
}

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
