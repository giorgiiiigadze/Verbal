//
//  ClientDetailView.swift
//  Verbal
//
//  One person, and whether they are worth chasing.
//
//  The tab lists who has been quoted and what was sent them; this answers the
//  question underneath that — how much of it was won, how often they say yes,
//  and what is still sitting with them unanswered. All of it derived from the
//  quotes already in the session, so there is nothing to fetch and nothing that
//  can disagree with the thread at the bottom of the page.
//
//  The figure that matters, what it is made of, then the detail. The middle of
//  those was a chart for a while — a bar per quote, then a running total — and
//  both drew a history nobody was asking this page for. `ClientMoneyBar` says
//  the same thing in a fifth of the height.
//

import SwiftUI
import UIKit

struct ClientDetailView: View {
    /// Who this page is about — their case-folded name, nothing more. The page
    /// holds no copy of them: everything drawn comes from `client` below, so an
    /// edit made in the thread at the bottom reaches the figures at the top.
    let key: ClientKey

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    /// Who the page is about now. Starts as the key it was pushed with and
    /// follows a rename — the page is keyed on the name, so without this a
    /// rename would leave it looking up a person who no longer exists and
    /// showing an empty history.
    @State private var currentKey: ClientKey?
    private var activeKey: ClientKey { currentKey ?? key }

    @State private var showRename = false
    @State private var renameText = ""
    @State private var toast: Toast?

    /// Where they are. Held by the page rather than by the sheet so the address
    /// is fetched once, survives the map being closed, and is still the same
    /// object when an edit lands on it.
    @State private var location = ClientLocation()
    @State private var showMap = false
    /// Set when the map sheet is being closed *in order to* edit the address,
    /// so the alert can wait for it to finish. Raising the alert in the same
    /// pass that dismisses the sheet loses it — the dismissal is what is on
    /// screen at that moment, and the alert never gets presented.
    @State private var editAddressAfterMap = false
    @State private var showAddressEditor = false
    @State private var addressText = ""

    /// This person as the session has them now.
    ///
    /// Matched case-insensitively on the name, the same rule `ClientsView`
    /// groups by — two spellings are one person there and must be one person
    /// here. Empty of quotes once the last of theirs is deleted, which is the
    /// only way a client stops existing — the page then shows their name over
    /// nothing for the moment before it is popped, rather than blanking.
    private var client: Client {
        let mine = session.quotes.filter {
            ($0.clientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == activeKey.id
        }
        return Client(mine) ?? Client(name: activeKey.name, quotes: [])
    }

    /// Changes whenever a figure on this page would.
    private var signature: String {
        client.quotes
            .map { "\($0.id)|\($0.total)|\($0.effectiveStatus)|\($0.currency ?? "")" }
            .joined(separator: ",") + "→" + currencyCode
    }

    /// Every quote of theirs, converted once into the display currency. Each
    /// figure below is a filter and a sum over this — one pass over the rates,
    /// and no two numbers on the page that can disagree about a conversion.
    @State private var points: [ClientQuotePoint] = []
    /// How far back the page is looking. All of it, until they say otherwise.
    @State private var range: ClientRange = .all

    /// The window in view, and the one before it for comparison.
    private var visible: [ClientQuotePoint] { points.within(range) }
    private var previous: [ClientQuotePoint] { points.before(range) }

    /// Quotes for the thread, cut by date rather than by membership of
    /// `visible` — a quote left out of the figures for want of a published rate
    /// still exists, and dropping it from the list too would read as deleted.
    private var visibleQuotes: [QuoteSummary] {
        guard let cutoff = range.cutoff() else { return client.quotes }
        return client.quotes.filter { $0.createdAt >= cutoff }
    }

    private var ranges: [ClientRange] { ClientRange.available(for: points) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                headline

                if !visible.isEmpty {
                    ClientMoneyBar(points: visible, currencyCode: currencyCode)
                }
                if ranges.count > 1 { rangePicker }

                section("Details") { stats }
                section("Quotes") {
                    // The same rows the tab draws, without the rail it hangs
                    // them from: there the rail ties a run of quotes to the
                    // client card above it, and here there is one client and
                    // the page is already about them.
                    ClientThread(quotes: visibleQuotes, showsRail: false)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.homeBackground))
        // The name is on the page, in the size it deserves. In the bar it would
        // be said twice, and the page would open with a heading it repeats.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // Left of the menu, and always there. Hiding it until an address
            // loads would make the bar rearrange itself a moment after the page
            // opens — and a client with no address is exactly who needs the
            // button, because tapping it is how one gets added.
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMap = true } label: {
                    Image(systemName: "map")
                }
                .accessibilityLabel("Client location")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = client.name
                        showRename = true
                    } label: {
                        Label("Rename client", systemImage: "character.cursor.ibeam")
                    }
                    Button {
                        editAddress()
                    } label: {
                        Label(location.hasAddress ? "Edit address" : "Add address",
                              systemImage: "mappin.and.ellipse")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Client options")
            }
        }
        // The same native alert the quote screen renames behind: one field, two
        // buttons, and nothing to learn.
        .alert("Rename client", isPresented: $showRename) {
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename(to: renameText) }
        } message: {
            Text("Changes the name on every quote of theirs. If someone else already has this name, the two are merged.")
        }
        .sheet(isPresented: $showMap, onDismiss: {
            guard editAddressAfterMap else { return }
            editAddressAfterMap = false
            editAddress()
        }) {
            // Both closures close the sheet from here rather than from inside
            // it: the card is a sheet presented on top of the map, and a sheet
            // with one of those up cannot dismiss itself.
            ClientMapSheet(clientName: client.name,
                           location: location) {
                editAddressAfterMap = true
                showMap = false
            } onClose: {
                showMap = false
            }
        }
        // The same one-field alert the rename uses. An address is a line of
        // text, and a sheet for it would be a screen to dismiss for something
        // that fits above the keyboard.
        .alert("Client address", isPresented: $showAddressEditor) {
            TextField("Street, town, or postcode", text: $addressText)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveAddress(addressText) }
        } message: {
            Text("Where the job is. Leave it empty to remove the address.")
        }
        .toast($toast)
        .task(id: activeKey.id) {
            await location.load(name: client.name, key: activeKey.id,
                                visits: session.visitStore.visits)
        }
        .task(id: signature) {
            points = await ClientQuotePoint.of(client.quotes, in: currencyCode)
            // A window that was on offer a moment ago may not be after an edit
            // or a deletion; landing on one that no longer exists would show an
            // empty page with no way back to the full history.
            if !ranges.contains(range) { range = .all }
        }
    }

    // MARK: - Renaming

    /// Writes the new name, then moves the page onto it.
    ///
    /// The list the page reads from is patched in place rather than refetched:
    /// the quotes themselves haven't changed, only who they point at, and a
    /// round trip would blank the figures on screen for as long as it took.
    private func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = client.name
        guard !trimmed.isEmpty, trimmed != previous else { return }
        let affected = client.quotes.map(\.id)

        Task {
            do {
                try await QuoteService.renameClient(from: previous, to: trimmed)
            } catch {
                toast = Toast(style: .error, message: "Couldn't rename this client")
                return
            }
            for id in affected {
                session.updateQuote(id: id) { $0.clientName = trimmed }
            }
            // A merge folds this person into someone else's history, so the key
            // has to move with them or the page would show only the quotes it
            // arrived with.
            currentKey = ClientKey(id: trimmed.lowercased(), name: trimmed)
            // A merge can fold this person into someone else's row, address and
            // all, so what is on screen is no longer known to be theirs. The
            // `.task` keyed on the id refetches as soon as the key moves.
            location.invalidate()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            toast = Toast(style: .success, message: "Renamed to \(trimmed)")
        }
    }

    // MARK: - Address

    /// Opens the editor on whatever the app already knows — their address, or
    /// the one from a visit booked with them.
    private func editAddress() {
        addressText = location.editingText
        showAddressEditor = true
    }

    /// Written the way the rename is: the page moves first and the round trip
    /// follows, so the map is right under the thumb rather than a moment later.
    private func saveAddress(_ newAddress: String) {
        let name = client.name
        Task {
            do {
                try await location.save(newAddress, name: name)
            } catch {
                toast = Toast(style: .error, message: "Couldn't save this address")
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: client.name, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(client.name)
                    .font(.robotoSlab(30, relativeTo: .title))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(span)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// How long they have been a client, and how much they have been sent.
    private var span: String {
        let count = "\(client.quotes.count) quote\(client.quotes.count == 1 ? "" : "s")"
        guard let first = client.quotes.map(\.createdAt).min() else { return count }
        return "Since \(first.formatted(.dateTime.month(.abbreviated).year())) · \(count)"
    }

    // MARK: - The figure

    /// What they are worth, which is what they said yes to — not what they were
    /// asked for. A quoted total on its own flatters every client equally.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(range == .all ? "Won" : "Won · last \(range.spoken ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            RollingAmount(value: visible.won.total.amount, code: currencyCode)
                .font(.robotoSlab(34, relativeTo: .largeTitle).monospacedDigit())
                .foregroundStyle(Color(.mainText))
            Text("of \(visible.total.formatted(in: currencyCode)) quoted")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let change { changeLine(change) }
        }
    }

    /// The same window again, one window earlier — the comparison a stock page
    /// gets for free from yesterday's close.
    ///
    /// Only when a window is chosen. Against "all" there is no earlier period
    /// to hold it up to, and inventing one (the last ninety days, say) would
    /// put a figure on the page that answers a question the user didn't ask.
    private var change: Double? {
        guard range != .all else { return nil }
        let now = visible.won.total.amount
        let then = previous.won.total.amount
        guard now > 0 || then > 0 else { return nil }
        return now - then
    }

    private func changeLine(_ delta: Double) -> some View {
        let rising = delta >= 0
        let tint = rising ? Color(.statusAcceptedText) : Color(.statusDeclinedText)
        return HStack(spacing: 4) {
            Image(systemName: rising ? "arrow.up" : "arrow.down")
                .font(.caption2.weight(.semibold))
            Text(AppCurrency.format(abs(delta), code: currencyCode))
                .font(.footnote.weight(.medium).monospacedDigit())
            Text("vs previous \(range.spoken ?? "")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.top, 2)
    }

    // MARK: - Range

    /// Only the windows that draw something different from "All" are offered;
    /// `ClientRange.available` decides, and a client with a short history gets
    /// no selector rather than four buttons that agree with each other.
    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(ranges) { option in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { range = option }
                } label: {
                    Text(option.label)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(option == range ? Color(.mainText) : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if option == range {
                                Capsule().fill(Color(.cardSurface))
                                Capsule().strokeBorder(Color(.separator), lineWidth: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Sections

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Stats

    private var stats: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stat("Accepted", acceptedText, detail: winRateText)
                divider
                stat("Average quote", averageText)
            }
            Divider()
            HStack(spacing: 0) {
                stat("Waiting", waitingText, detail: oldestText)
                divider
                stat("Last quoted", lastQuotedText)
            }
            Divider()
            HStack(spacing: 0) {
                stat("Largest quote", largestText)
                divider
                stat("Declined", declinedText)
            }
        }
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
    }

    private func stat(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// How many of the client's answered quotes went their way. Not the same
    /// denominator as the line above it, and deliberately so — see below.
    private var decided: Int { visible.won.count + visible.declined.count }

    /// Out of everything they have been sent.
    ///
    /// It read "1 of 1" against a client holding four quotes, which is true of
    /// the ones they answered and true of nothing the reader is looking at. The
    /// figure a page about a client has to survive is the one they can check
    /// against the list underneath it, so the denominator is every quote in the
    /// window — the same number the header counts.
    private var acceptedText: String {
        guard !visible.isEmpty else { return "—" }
        return "\(visible.won.count) of \(visible.count)"
    }

    /// The rate underneath, over answers rather than over everything.
    ///
    /// Both numbers are needed and neither can do the other's job: counting the
    /// undecided as losses reads as a poor client when they simply haven't
    /// replied yet, and counting only the decided hides how much is still out
    /// there. So the line states its own denominator and can't be misread as
    /// disagreeing with the count above.
    private var winRateText: String? {
        guard decided > 0 else {
            return visible.isEmpty ? nil : "None answered yet"
        }
        let rate = Double(visible.won.count) / Double(decided)
        return rate.formatted(.percent.precision(.fractionLength(0))) + " of answered"
    }

    private var averageText: String {
        let total = visible.total
        guard total.counted > 0 else { return "—" }
        return AppCurrency.format(total.amount / Double(total.counted), code: currencyCode)
    }

    private var waitingText: String {
        let waiting = visible.waiting.total
        return waiting.counted > 0 ? waiting.formatted(in: currencyCode) : "Nothing"
    }

    /// Only when something is waiting — an age under "Nothing" would be an age
    /// of nothing.
    private var oldestText: String? {
        guard let oldest = visible.waiting.map(\.date).min() else { return nil }
        return "Oldest \(oldest.formatted(.relative(presentation: .named)))"
    }

    private var lastQuotedText: String {
        visible.map(\.date).max().map { quoteDateLabel($0) } ?? "—"
    }

    /// The biggest single job they have been quoted, won or not — the ceiling
    /// on what this client is worth asking for.
    private var largestText: String {
        guard let largest = visible.map(\.amount).max() else { return "—" }
        return AppCurrency.format(largest, code: currencyCode)
    }

    private var declinedText: String {
        let declined = visible.declined.total
        guard declined.counted > 0 else { return "None" }
        return "\(declined.counted) · \(declined.formatted(in: currencyCode))"
    }
}
