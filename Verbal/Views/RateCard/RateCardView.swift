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
    /// Line-item prices this card has filled in. Nil until it's known, so the
    /// header says nothing rather than claiming zero.
    @State private var fillCount: Int?
    @State private var searchText = ""
    /// Nil is "All". Holds a raw type ("labor"), not a label.
    @State private var typeFilter: String?
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
            } else if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(.homeBackground))
        .navigationTitle("Rate card")
        // The same search Home has, in the same place. A card of eight rates
        // doesn't need it; the card this screen is trying to encourage does.
        .searchable(text: $searchText, prompt: "Search rates")
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
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
                toast = Toast(style: .success,
                              message: "\(added) rate\(added == 1 ? "" : "s") saved")
            }
        }
        .task {
            // Seed from the splash-time preload so the list shows instantly.
            if !hasLoaded {
                items = session.rateCard
                hasLoaded = session.listsLoaded
            }
            // The heading is seeded the same way, and every time this tab is
            // opened rather than only the first. Held back, it wrote "4 rates
            // saved" and then rewrote itself once the count landed — a line
            // changing under the reader for no reason they can see.
            fillCount = session.rateCardFillCount ?? fillCount
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

    /// What the card is, and what it has actually done. The screen used to open
    /// straight into rows, with nothing at the top saying either — so a page of
    /// identical cards was all it ever amounted to.
    private var summaryHeader: some View {
        Group {
            if let fillCount, fillCount > 0 {
                Text(filledInLine(fillCount))
            } else {
                Text("\(items.count) rate\(items.count == 1 ? "" : "s") saved")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two weights on one line, built as an attributed string rather than by
    /// adding two `Text`s — that operator is deprecated as of iOS 26.
    ///
    /// The count of rates leads with nothing: it's four cards, you can see that.
    /// The prices they've filled in is the number that says whether keeping them
    /// was worth it, so it goes first and takes the only emphasis on the line.
    private func filledInLine(_ fillCount: Int) -> AttributedString {
        var filled = AttributedString(
            "\(fillCount) price\(fillCount == 1 ? "" : "s") filled in")
        filled.font = .subheadline.weight(.medium)
        filled.foregroundColor = Color(.mainText)

        var from = AttributedString(
            " from your \(items.count) rate\(items.count == 1 ? "" : "s")")
        from.font = .subheadline
        from.foregroundColor = .secondary

        return filled + from
    }

    private var list: some View {
        List {
            summaryHeader
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 12, trailing: 20))

            if typeOptions.count > 1 {
                typeFilterRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0))
            }

            if !candidates.isEmpty, searchText.isEmpty, typeFilter == nil {
                readyToAddCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 18, trailing: 20))
            }

            if groups.isEmpty {
                noMatchesRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 0, trailing: 20))
            }

            ForEach(groups, id: \.label) { group in
                // Set and placed exactly as Home sets its status headings, and
                // as a normal row rather than a Section header for the same
                // reason: it scrolls away with its rates instead of pinning to
                // the top of the screen.
                Text(group.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))

                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    rateRow(item,
                            isFirst: index == 0,
                            isLast: index == group.items.count - 1)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Filtering

    /// The types actually present, so the row never offers a filter that would
    /// empty the screen.
    private var typeOptions: [String] {
        let present = Set(items.map(\.type))
        return Self.typeOrder.filter(present.contains)
            + present.subtracting(Self.typeOrder).sorted()
    }

    private static let typeOrder = ["labor", "material", "other"]
    private static let typeLabels = ["labor": "Labor", "material": "Materials",
                                     "other": "Other"]

    private static func label(for type: String) -> String {
        typeLabels[type] ?? type.capitalized
    }

    private var typeFilterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterChip("All", isSelected: typeFilter == nil) { typeFilter = nil }
                ForEach(typeOptions, id: \.self) { type in
                    filterChip(Self.label(for: type), isSelected: typeFilter == type) {
                        // Tapping the active one clears it, so the row doesn't
                        // need "All" to be a target you must aim back at.
                        typeFilter = typeFilter == type ? nil : type
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(_ title: String,
                            isSelected: Bool,
                            select: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.18)) { select() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : Color(.mainText))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color(.royalBlue600) : Color(.cardSurface),
                            in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? .clear : Color(.separator),
                                           lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    /// Rates by type, after the search and the chip, in the order the add form
    /// offers them. Anything unrecognised sorts last so a rate can't go missing.
    private var groups: [(label: String, items: [RateCardItem])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = items.filter { item in
            guard typeFilter == nil || item.type == typeFilter else { return false }
            guard !query.isEmpty else { return true }
            return item.name.lowercased().contains(query)
                || (item.unit?.lowercased().contains(query) ?? false)
        }
        let byType = Dictionary(grouping: filtered, by: \.type)
        // Counted in the heading, the way Home writes "Drafts · 5".
        let known = Self.typeOrder.compactMap { type in
            byType[type].map { ("\(Self.label(for: type)) · \($0.count)", $0) }
        }
        let rest = byType.keys.filter { !Self.typeOrder.contains($0) }.sorted().map { type in
            let group = byType[type] ?? []
            return ("\(Self.label(for: type)) · \(group.count)", group)
        }
        return known + rest
    }

    private var noMatchesRow: some View {
        Text(searchText.isEmpty
             ? "Nothing saved under this type yet."
             : "No rates match “\(searchText)”.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Rows

    /// One saved price, inside its type's card.
    ///
    /// Name and money on the top line because that pairing is what's being
    /// compared down the column; the unit sits under the name where it qualifies
    /// the job rather than competing with the number.
    private func rateRow(_ item: RateCardItem, isFirst: Bool, isLast: Bool) -> some View {
        Button {
            itemToEdit = item
        } label: {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(alignment: .bottom) {
                if !isLast { Divider().padding(.leading, 16) }
            }
            .background(groupedCardBackground(isFirst: isFirst, isLast: isLast))
        }
        .buttonStyle(CardPressStyle())
        .contentShape(.contextMenuPreview, Self.groupedCardShape(isFirst: isFirst, isLast: isLast))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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

    private static func groupedCardShape(isFirst: Bool, isLast: Bool) -> UnevenRoundedRectangle {
        let radius: CGFloat = 18
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? radius : 0,
            bottomLeadingRadius: isLast ? radius : 0,
            bottomTrailingRadius: isLast ? radius : 0,
            topTrailingRadius: isFirst ? radius : 0,
            style: .continuous)
    }

    /// A type's rates read as one card, but a List can only paint a row at a
    /// time. Drawn per row, the border would lay a hairline across every seam
    /// and double up with the dividers — so its horizontal edges are pushed just
    /// outside the row and clipped, leaving the sides and one outline.
    private func groupedCardBackground(isFirst: Bool, isLast: Bool) -> some View {
        let shape = Self.groupedCardShape(isFirst: isFirst, isLast: isLast)
        return shape
            .fill(Color(.cardSurface))
            .overlay(shape.strokeBorder(Color(.separator), lineWidth: 0.5))
            .padding(.top, isFirst ? 0 : -1)
            .padding(.bottom, isLast ? 0 : -1)
            .clipped()
    }

    /// Prices already spoken into quotes, waiting to become rates. The blue is
    /// the app's "this card means something" fill, and it earns it here: it's
    /// the only thing on the screen asking to be tapped.
    private var readyToAddCard: some View {
        Button {
            showCandidates = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(candidates.count) price\(candidates.count == 1 ? "" : "s") ready to add")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(.blueAccentText))
                    Text("Spoken into recent quotes, not saved here yet")
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
        // Best effort, and deliberately last: the header line is the least of
        // what this screen owes the user, and a count that won't come back
        // shouldn't cost them the rates themselves.
        if let count = try? await QuoteService.rateCardFillCount() {
            fillCount = count
            // So the next visit to this tab opens on the same number it left on.
            session.cacheRateCardFillCount(count)
        }
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

// MARK: - Ready to add

/// The prices already spoken into quotes, offered back as rates to keep.
///
/// Everything arrives selected. These are prices the user chose once already, so
/// the question is which to leave out, not which to take — and the sheet is only
/// worth opening if saying yes to all of it is one tap.
private struct ReadyToAddSheet: View {
    let candidates: [RateCandidate]
    var onAdded: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<UUID> = []
    @State private var isSaving = false

    private var chosen: [RateCandidate] {
        candidates.filter { !skipped.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready to add")
                    .font(.robotoSlab(22, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))
                Spacer()
                Button(role: .close) { dismiss() }
            }
            .padding(.horizontal, 24)

            Text("You priced these by voice. Save them and the next quote prices itself.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(candidates) { candidate in
                        row(candidate)
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, 24)
        .safeAreaInset(edge: .bottom) {
            Button { save() } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(chosen.isEmpty
                             ? "Nothing selected"
                             : "Save \(chosen.count) rate\(chosen.count == 1 ? "" : "s")")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(chosen.isEmpty
                            ? Color(.royalBlue600).opacity(0.4)
                            : Color(.royalBlue600),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(chosen.isEmpty || isSaving)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color(.surface))
        }
        .presentationDetents([.height(detentHeight), .large])
        .presentationCornerRadius(28)
        .presentationBackground(Color(.surface))
    }

    /// Sized to the list, like the sheet that offers unpriced lines: three
    /// candidates shouldn't open onto a void, twelve shouldn't hide the button.
    private var detentHeight: CGFloat {
        let visible = CGFloat(min(candidates.count, 6))
        return min(220 + visible * 62, 660)
    }

    private func row(_ candidate: RateCandidate) -> some View {
        let isChosen = !skipped.contains(candidate.id)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.18)) {
                if isChosen { skipped.insert(candidate.id) } else { skipped.remove(candidate.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? Color(.royalBlue600) : Color(.separator))
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text(Self.label(for: candidate.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppCurrency.format(candidate.unitPrice))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    if let unit = candidate.unit, !unit.isEmpty {
                        Text("per \(unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .opacity(isChosen ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private static func label(for type: String) -> String {
        switch type {
        case "labor": return "Labor"
        case "material": return "Material"
        default: return type.capitalized
        }
    }

    private func save() {
        isSaving = true
        Task {
            var saved = 0
            for candidate in chosen {
                do {
                    try await QuoteService.addRateCardItem(
                        name: candidate.name, unit: candidate.unit,
                        unitPrice: candidate.unitPrice, type: candidate.type)
                    saved += 1
                } catch {
                    // Keep going: one failed write shouldn't cost the others,
                    // and the count reported is the count that landed.
                    continue
                }
            }
            isSaving = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAdded(saved)
            dismiss()
        }
    }
}

// MARK: - Add form

/// Presses the card rather than the row it sits in. A bare tap gesture leaves
/// the List to draw its own highlight, which runs the full width of the row and
/// squares off the corners the card was drawn with — so the feedback lands on a
/// shape the user can't see. Matches how a quote row behaves.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// New rate, or a correction to one that exists.
///
/// The old version was a Settings-style form: four fields of equal weight, a
/// full-height sheet, and a "Custom…" unit that opened a second field — which is
/// how one card ended up holding both "m²" and "square meters". It also had no
/// idea what was already saved, so the same job could be entered twice at
/// different prices, and the whole card goes to the model on every extraction:
/// two prices for one job means it picks one, and the user never learns which.
///
/// So the warning is the centrepiece. It watches what's being typed and names
/// the rate it collides with, with an offer to correct that one instead.
private struct AddRateItemView: View {
    /// What's already saved, so a collision can be spotted while it's typed
    /// rather than discovered months later in a wrong quote.
    let existing: [RateCardItem]
    /// Set when the sheet opened to correct a specific rate.
    var editing: RateCardItem?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "each"
    @State private var priceText = ""
    @State private var type = "labor"
    @State private var isSaving = false
    /// The rate being corrected — either the one passed in, or one the user
    /// adopted from the duplicate warning.
    @State private var target: RateCardItem?
    @FocusState private var nameFocused: Bool

    private let types = ["labor", "material", "other"]
    private let commonUnits = ["each", "m²", "m", "hour", "day", "job", "litre", "kg"]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var price: Double? {
        let cleaned = priceText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    /// A price is required. A rate without one can't price anything — it just
    /// rides along in every extraction request as noise.
    private var canSave: Bool {
        !trimmedName.isEmpty && (price ?? 0) > 0
    }

    /// The saved rate this one looks like, if any. Shares its comparison with
    /// the save-from-quote sheet, so both doors into the rate card agree on
    /// what counts as the same job.
    private var collision: RateCardItem? {
        guard target == nil, trimmedName.count >= 3 else { return nil }
        return existing.first { $0.id != editing?.id && $0.looksLike(trimmedName) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(target == nil ? "New rate" : "Edit rate")
                    .font(.robotoSlab(22, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))
                Spacer()
                Button(role: .close) { dismiss() }
            }
            .padding(.horizontal, 24)

            Text("Verbal fills this in automatically next time you quote the same work.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 24)

            // The inset moved off the sheet and onto each piece inside it, so
            // this scroll view spans the full width. It is what clips the unit
            // chips, and inset by 24 it cut them off short of the edge.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("What is it? (e.g. Re-tiling)", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.sentences)

                    if let collision { duplicateWarning(collision) }

                    HStack(spacing: 4) {
                        Text(AppCurrency.current.symbol).foregroundStyle(.secondary)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    .font(.body.monospacedDigit())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.cardSurface),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )

                    // Type and unit are the same question asked twice — pick one
                    // of a short list — so they're asked the same way. This was
                    // a segmented control sitting a line above the unit chips:
                    // the only stock iOS control in a sheet drawn by hand, and
                    // a second idiom for a choice the row below already had one
                    // for. It also truncated "Material" to "Mater…" at larger
                    // text sizes, which a chip that can scroll never does.
                    chipRow("Type", options: types,
                            display: { $0.capitalized }, selection: $type)

                    // Tappable rather than a picker with a "Custom…" escape
                    // hatch: the two-step is what let the same unit be typed
                    // two different ways.
                    chipRow("Per", options: unitOptions, selection: $unit)
                }
                .padding(.top, 20)
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, 24)
        .safeAreaInset(edge: .bottom) {
            Button { save() } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(target == nil ? "Save rate" : "Update rate").font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSave ? Color(.royalBlue600) : Color(.royalBlue600).opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color(.surface))
        }
        // The chip row stands ~28pt taller than the segmented control it
        // replaced — a caption above it, and a taller target under the thumb.
        .presentationDetents([.height(560)])
        .presentationCornerRadius(28)
        .presentationBackground(Color(.surface))
        .task {
            if let editing { adopt(editing) }
            try? await Task.sleep(for: .seconds(0.35))
            nameFocused = true
        }
    }

    /// Always offers the current unit, so a rate saved with something unusual
    /// doesn't lose it just by being opened.
    private var unitOptions: [String] {
        commonUnits.contains(unit) ? commonUnits : [unit] + commonUnits
    }

    /// A labelled row of chips — the sheet's one way of choosing from a short
    /// list, so type and unit stop being two controls for the same job.
    ///
    /// Always scrollable, even where the options fit today: at accessibility
    /// text sizes three chips stop fitting on a line, and scrolling past them is
    /// better than a row that clips or wraps.
    private func chipRow(_ label: String,
                         options: [String],
                         display: @escaping (String) -> String = { $0 },
                         selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            // Runs edge to edge, like the chips on a quote. The row steps back
            // out of the content inset and puts it back on the chips
            // themselves, so they start in line with the fields above but keep
            // scrolling to the sheet's own edges — the last chip no longer sits
            // against an invisible wall with clear space beyond it.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        chip(display(option),
                             isSelected: selection.wrappedValue == option) {
                            selection.wrappedValue = option
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -24)
        }
    }

    private func chip(_ title: String,
                      isSelected: Bool,
                      select: @escaping () -> Void) -> some View {
        Button {
            // A segmented control ticks under the thumb on every change. Losing
            // that was the one thing the stock picker did better, so it comes
            // back explicitly — and the fill moves rather than cutting.
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.18)) { select() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : Color(.mainText))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Color(.royalBlue600) : Color(.cardSurface),
                            in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? .clear : Color(.separator),
                                           lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func duplicateWarning(_ item: RateCardItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(LineItemRow.amber)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("You already have “\(item.name)”\(item.priceText.map { " at \($0)" } ?? "")")
                    .font(.footnote)
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Correct that one instead") { adopt(item) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.blueAccentText))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LineItemRow.amber.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Load an existing rate into the form and switch to correcting it.
    private func adopt(_ item: RateCardItem) {
        target = item
        name = item.name
        unit = item.unit ?? "each"
        type = item.type
        priceText = item.unitPrice.map {
            $0 == $0.rounded() ? String(Int($0)) : String($0)
        } ?? ""
    }

    private func save() {
        isSaving = true
        Task {
            if let target {
                try? await QuoteService.updateRateCardItem(
                    id: target.id, name: trimmedName, unit: unit,
                    unitPrice: price, type: type)
            } else {
                try? await QuoteService.addRateCardItem(
                    name: trimmedName, unit: unit, unitPrice: price, type: type)
            }
            isSaving = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(Color(.mainText))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
    }
}
