//
//  RateCardView.swift
//  Verbal
//
//  The user's saved prices (labor / material / other). These feed the AI
//  extraction so known items get priced automatically instead of flagged.
//

import SwiftUI

struct RateCardView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.colorScheme) private var scheme
    @State private var items: [RateCardItem] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var showAdd = false
    @State private var itemToDelete: RateCardItem?
    /// The rate opened for correction.
    @State private var itemToEdit: RateCardItem?
    @State private var toast: Toast?
    /// True when the last fetch failed — separates "no rates saved" from
    /// "couldn't reach the server", which look identical without it.
    @State private var loadFailed = false
    /// True once this device has seen a rate card with something in it.
    ///
    /// It separates someone who has never had rates from someone who had them
    /// and cleared them out, which is the difference between a pitch and a
    /// statement of fact. Held on the device rather than derived from the
    /// server, because the server can only say what is there now — the whole
    /// question is what used to be. A returning user on a new phone is told
    /// about the feature once more, which is the harmless way to be wrong.
    @AppStorage("hasSavedRates") private var hasSavedRates = false
    @State private var showCandidates = false

    /// Prices spoken into recent quotes that aren't saved here yet. Read from
    /// the session rather than held here: preloaded with the lists so the offer
    /// is on screen with everything else, and derived from the rate card so
    /// accepting one takes it off the list without a refetch.
    private var candidates: [RateCandidate] { session.rateCandidates }

    var body: some View {
        Group {
            if items.isEmpty && !hasLoaded {
                // Still loading first paint — stay blank, not "no prices".
                Color(.homeBackground)
            } else if items.isEmpty && loadFailed {
                // Don't invite someone to save their usual prices when the app
                // simply couldn't reach the ones they already have.
                errorState
            } else if items.isEmpty, hasSavedRates {
                // Someone who has kept rates before and cleared them out is told
                // so plainly. Pitching the feature again to a user who has been
                // using it for months reads as an app that wasn't paying
                // attention.
                noRatesState
            } else if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(.homeBackground))
        .navigationTitle("Rate card")
        // Small and fixed in the bar rather than a large heading that grows and
        // collapses with the scroll — the large title spent its height on the
        // name of a screen the header button already announced. Fixed also
        // means it is there in every state, including the two empty ones where
        // a collapsing title has nothing to collapse against.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add rate")
            }
        }
        // Pushed onto Home's stack, so it inherits Home's tab bar. Hidden here:
        // this is a screen you went into to do one thing, not one of the app's
        // standing places, and leaving the bar under it invites a sideways jump
        // out of a job half-done. The back button is the way out.
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            AddRateItemView(existing: items)
        }
        // Tapping a rate corrects it. Until now a price could only be changed by
        // deleting the rate and retyping it, which is how the card came to hold
        // the same job twice at two different prices.
        .sheet(item: $itemToEdit, onDismiss: { Task { await load() } }) { item in
            AddRateItemView(existing: items, editing: item)
        }
        .sheet(isPresented: $showCandidates, onDismiss: { Task { await load() } }) {
            ReadyToAddSheet(candidates: candidates) { added in
                // Delayed past the sheet's dismissal: set now, the toast starts
                // its life behind the sheet and has largely expired by the time
                // this screen is visible. The quote screen learned the same
                // thing about reporting a delete.
                //
                // And zero saved is not a success. Every write failing —
                // offline, most likely — used to report "0 rates saved" in
                // green, on a screen still listing every one of them.
                Task {
                    try? await Task.sleep(for: .seconds(0.4))
                    toast = added > 0
                        ? Toast(style: .success,
                                message: "\(added) rate\(added == 1 ? "" : "s") saved")
                        : Toast(style: .error, message: "Couldn't save those rates")
                }
            }
        }
        .task {
            // Seed from the splash-time preload so the list shows instantly.
            if !hasLoaded {
                items = session.rateCard
                hasLoaded = session.listsLoaded
            }
            await load()
        }
        // Bootstrap can finish after this view has already read an empty list —
        // signing in reaches the tabs before the preload returns.
        .onChange(of: session.listsLoaded) { _, loaded in
            guard loaded, items.isEmpty, !session.rateCard.isEmpty else { return }
            items = session.rateCard
            loadFailed = false
        }
        .refreshable { await load() }
        .alert("Delete this rate?", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        ), presenting: itemToDelete) { item in
            Button("Delete", role: .destructive) {
                Task { await delete(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("This removes “\(item.name)” from your rate card. This can't be undone.")
        }
        .toast($toast)
    }

    private var list: some View {
        List {
            if !candidates.isEmpty {
                readyToAddCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 18, trailing: 20))
            }

            ForEach(groups, id: \.label) { group in
                // Set and placed exactly as Home sets its date headings, and
                // as a normal row rather than a Section header for the same
                // reason: it scrolls away with its rates instead of pinning to
                // the top of the screen.
                Text(group.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))

                ForEach(group.items) { item in
                    rateRow(item)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Grouping

    private static let typeOrder = ["labor", "material", "other"]
    private static let typeLabels = ["labor": "Labor", "material": "Materials",
                                     "other": "Other"]

    private static func label(for type: String) -> String {
        typeLabels[type] ?? type.capitalized
    }

    /// Rates by type, in the order the add form offers them. Anything
    /// unrecognised sorts last so a rate can't go missing.
    private var groups: [(label: String, items: [RateCardItem])] {
        let byType = Dictionary(grouping: items, by: \.type)
        // Bare labels. The count went when Home's did — it counts what is
        // directly beneath it, which the eye does faster than it reads.
        let known = Self.typeOrder.compactMap { type in
            byType[type].map { (Self.label(for: type), $0) }
        }
        let rest = byType.keys.filter { !Self.typeOrder.contains($0) }.sorted().map { type in
            (Self.label(for: type), byType[type] ?? [])
        }
        return known + rest
    }

    // MARK: - Rows

    /// One saved price, on its own card.
    ///
    /// It used to be a segment of a per-type card, joined to its neighbours by
    /// dividers; now each rate stands alone, drawn as the same card a quote gets
    /// on Home — so a price on this screen and a quote on that one read as the
    /// same kind of object, which they nearly are.
    ///
    /// Name and money on the top line because that pairing is what's being
    /// compared down the column; the unit sits under the name where it qualifies
    /// the job rather than competing with the number.
    private func rateRow(_ item: RateCardItem) -> some View {
        Button {
            itemToEdit = item
        } label: {
            HStack(spacing: 12) {
                // A small tinted plate at the head of the card, so each rate
                // reads as a labelled thing rather than a bare line. Surface
                // tone with a hairline — a step off the cardSurface behind it.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.surface))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: "tag.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(.mainText))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(item.name)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color(.mainText))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let unitPrice = item.unitPrice {
                            Text(AppCurrency.format(unitPrice))
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color(.mainText))
                                .lineLimit(1)
                        } else {
                            // The same amber a quote uses for a line it couldn't
                            // price, saying the same thing: this one needs you.
                            HStack(spacing: 6) {
                                Circle().fill(LineItemRow.amber).frame(width: 6, height: 6)
                                Text("Set price")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(LineItemRow.amber)
                            }
                        }
                    }
                    if let unit = item.unit, !unit.isEmpty {
                        Text("per \(unit)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(.cardSurface), in: Self.cardShape)
            .overlay(Self.cardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
            // A shadow soft enough to lift the card off the page without
            // announcing itself. Tied to the scheme rather than a fixed black:
            // in the dark the page is already near-black and a black shadow is
            // invisible, so it lightens to almost nothing and the border does
            // the lifting instead.
            .shadow(color: .black.opacity(scheme == .dark ? 0.26 : 0.10),
                    radius: 8, x: 0, y: 3)
        }
        .buttonStyle(CardPressStyle())
        .contentShape(.contextMenuPreview, Self.cardShape)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // The gap between cards, so each reads as its own rather than a strip.
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
        .contextMenu {
            Button {
                itemToEdit = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                itemToDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // Two actions, in the order and tints a quote row uses. Delete on its
        // own opened as one wide red block, which reads as a warning where a
        // quote's swipe reads as a choice.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // No .destructive role: it would animate the row out on tap, before
            // the confirmation alert is answered.
            Button {
                itemToDelete = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                itemToEdit = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color(.royalBlue300))
        }
    }

    /// One radius for every rate card, matching the quote card on Home.
    private static let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    /// Prices already spoken into quotes, waiting to become rates. The blue is
    /// the app's "this card means something" fill, and it earns it here: it's
    /// the only thing on the screen asking to be tapped.
    private var readyToAddCard: some View {
        Button {
            showCandidates = true
        } label: {
            HStack(spacing: 12) {
                // The tag, the same mark the header button on Home wears. It
                // says at a glance that this card is about the rate card rather
                // than about the quote that produced the prices.
                Image(systemName: "tag")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.blueAccentText))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(candidates.count) price\(candidates.count == 1 ? "" : "s") ready to add")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(.blueAccentText))
                    Text("Spoken into your quotes, not saved here yet")
                        .font(.footnote)
                        .foregroundStyle(Color(.blueAccentText).opacity(0.75))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.blueAccentText))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.royalBlue25),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(CardPressStyle())
    }

    /// A cousin of the Home empty state, deliberately quieter. This is a
    /// supporting tab, and if every screen opens with a hero card then none of
    /// them is the important one — so the sample is two rows rather than a whole
    /// quote, and the heading stays plain rather than taking the display serif.
    private var emptyState: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                sampleRates
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .frame(height: 104, alignment: .top)
                    .clipped()
                    .mask(
                        LinearGradient(colors: [.black, .black, .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Save your usual prices")
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))

                    Text("Verbal fills them in automatically when you quote the same work. You'll also be offered them after a quote comes back with prices missing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showAdd = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add a rate").fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 46)
                        .background(Color(.royalBlue600), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
            .background(Color(.royalBlue25),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }

    /// The card is empty, but it hasn't always been. Nothing is being sold here
    /// — the user knows what a rate card is, they just emptied theirs, and the
    /// screen's job is to say so and offer the way back.
    private var noRatesState: some View {
        // `rectangle.stack` is the tab's own icon unfilled: the bar is showing
        // the solid version at the same moment, so the hollow one reads as the
        // same thing with nothing in it.
        EmptyStateMessage(
            icon: "rectangle.stack",
            title: "No rates saved",
            message: "Add the prices you quote most and they'll fill themselves in next time."
        ) {
            EmptyStatePill(title: "Add a rate", icon: "plus") { showAdd = true }
            // Only when there is something behind it. A suggestion that opens an
            // empty list is worse than no suggestion.
            if !candidates.isEmpty {
                EmptyStatePill(title: "Add from a recent quote", icon: "text.quote") {
                    showCandidates = true
                }
            }
        }
    }

    /// The fetch failed and there's nothing cached to fall back on. Matches the
    /// shape Home uses for the same situation.
    private var errorState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(.mainText))
                .padding(.bottom, 6)
            Text("Couldn't load your rates")
                .font(.headline)
                .foregroundStyle(Color(.mainText))
            Text("Check your connection and try again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await load() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color(.blueAccentText))
            .padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Two rates that don't exist, drawn the way real ones are.
    private var sampleRates: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.sampleRates.enumerated()), id: \.offset) { index, rate in
                if index > 0 { Divider() }
                HStack {
                    Text(rate.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(AppCurrency.format(rate.price)) / \(rate.unit)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 11)
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private static let sampleRates: [(name: String, price: Double, unit: String)] = [
        ("Re-tiling", 45, "m²"),
        ("Replace toilet", 90, "each")
    ]

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await QuoteService.fetchRateCard()
            items = fetched
            // Only ever set, never cleared: emptying the card is exactly the
            // thing this is meant to remember.
            if !fetched.isEmpty { hasSavedRates = true }
            // Settings decides from this cache whether a currency change would
            // redenominate saved prices, so it has to see what was just added
            // here — but only ever a list that was actually fetched.
            session.cacheRateCard(fetched)
            loadFailed = false
        } catch {
            // Keep what's on screen, and above all don't cache the failure.
            // This used to read `?? []`, so one visit to this tab offline
            // emptied the list, wrote that emptiness into the session, and left
            // Settings believing there were no saved prices to protect — which
            // silently disarmed the warning before a currency change rewrites
            // every rate.
            // Cancelled is not failed — this tab's load is called off every
            // time the user leaves it, and saying so is telling them their own
            // tap went wrong.
            guard !error.isCancellation else { return }
            loadFailed = true
            // Silent offline: the banner already says it.
            if !items.isEmpty, network.isOnline {
                toast = Toast(style: .error, message: "Couldn't refresh rates")
            }
        }
        hasLoaded = true
        if let spoken = try? await QuoteService.recentSpokenPrices() {
            session.cacheSpokenPrices(spoken)
        }
    }

    private func delete(_ item: RateCardItem) async {
        do {
            try await QuoteService.deleteRateCardItem(id: item.id)
            withAnimation(HomeView.rowRemoval) { items.removeAll { $0.id == item.id } }
            toast = Toast(style: .success, message: "Rate deleted")
        } catch {
            toast = Toast(style: .error, message: "Couldn't delete rate")
        }
    }
}
