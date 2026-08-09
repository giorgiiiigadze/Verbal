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
            ForEach(items) { item in
                Button {
                    itemToEdit = item
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.headline)
                                .foregroundStyle(Color(.mainText))
                            Text(item.type.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let price = item.priceText {
                            Text(price)
                                .font(.subheadline.monospacedDigit().weight(.medium))
                                .foregroundStyle(Color(.blueAccentText))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.royalBlue25), in: Capsule())
                        } else {
                            Text("No price")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .background(Color(.cardSurface),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                }
                .buttonStyle(CardPressStyle())
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // No .destructive role: it would animate the row out on tap,
                    // before the confirmation alert is answered.
                    Button {
                        itemToDelete = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

                    // Its own line. Squeezed into 168pt beside the price it was
                    // already truncating "Material" to "Mater…", and a segmented
                    // control that can't fit its own labels only gets worse at
                    // larger text sizes.
                    Picker("Type", selection: $type) {
                        ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    // Tappable rather than a picker with a "Custom…" escape
                    // hatch: the two-step is what let the same unit be typed
                    // two different ways.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Per")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Runs edge to edge, like the chips on a quote. The row
                        // steps back out of the content inset and puts it back
                        // on the chips themselves, so they start in line with
                        // the fields above but keep scrolling to the sheet's
                        // own edges — the last unit no longer sits against an
                        // invisible wall with clear space beyond it.
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(unitOptions, id: \.self) { option in
                                    Button { unit = option } label: {
                                        Text(option)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(unit == option
                                                             ? .white : Color(.mainText))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(unit == option
                                                        ? Color(.royalBlue600) : Color(.cardSurface),
                                                        in: Capsule())
                                            .overlay(
                                                Capsule().strokeBorder(
                                                    unit == option ? .clear : Color(.separator),
                                                    lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.horizontal, -24)
                    }
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
                .frame(height: 54)
                .background(canSave ? Color(.royalBlue600) : Color(.royalBlue600).opacity(0.4),
                            in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color(.surface))
        }
        .presentationDetents([.height(530)])
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
