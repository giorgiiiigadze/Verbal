//
//  ClientDetailView.swift
//  Verbal
//
//  One person, their value at a glance, recent quotes and useful contact detail.
//  Quote-derived sections stay live with the session; location and visit data
//  fill in the client information the quote summary itself does not carry.
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
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var showsAllQuotes = false

    /// On the white canvas, only the grouped information cards need lift.
    /// Keep the shadow out of dark mode, where the card outline already carries
    /// the separation without adding a muddy halo.
    private var cardShadow: Color {
        colorScheme == .light ? Color.black.opacity(0.07) : .clear
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                profileHeader
                summaryCard
                quotesSection
                activitySection
                clientInformationSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color(.homeBackground))
        // The name is on the page, in the size it deserves. In the bar it would
        // be said twice, and the page would open with a heading it repeats.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showMap = true } label: {
                        Label("View location", systemImage: "map")
                    }
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

    // MARK: - Profile

    private var profileHeader: some View {
        VStack(spacing: 10) {
            InitialsAvatar(name: client.name, size: 72)

            Text(client.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(.mainText))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(span)
                .font(.footnote)
                .foregroundStyle(.secondary)

        }
        .frame(maxWidth: .infinity)
    }

    /// How long they have been a client, and how much they have been sent.
    private var span: String {
        let count = "\(client.quotes.count) quote\(client.quotes.count == 1 ? "" : "s")"
        guard let first = client.quotes.map(\.createdAt).min() else { return count }
        return "Since \(first.formatted(.dateTime.month(.abbreviated).year())) · \(count)"
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: 0) {
            summaryMetric(totalQuotedText, label: "Total quoted")
            summaryDivider
            summaryMetric("\(client.quotes.count)", label: "Quotes")
            summaryDivider
            summaryMetric(acceptedValueText, label: "Accepted")
        }
        .padding(.vertical, 16)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: cardShadow, radius: 12, y: 4)
    }

    private func summaryMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5, height: 36)
    }

    private var totalQuotedText: String {
        guard !points.isEmpty else { return client.singleCurrencyTotal ?? "—" }
        return points.total.formatted(in: currencyCode)
    }

    private var acceptedValueText: String {
        guard !points.isEmpty else { return "—" }
        let accepted = points.won.total
        return accepted.counted > 0 ? accepted.formatted(in: currencyCode) : AppCurrency.format(0, code: currencyCode)
    }

    // MARK: - Quotes

    private var displayedQuotes: [QuoteSummary] {
        showsAllQuotes ? client.quotes : Array(client.quotes.prefix(3))
    }

    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeading("Quotes")
                Spacer()
                if client.quotes.count > 3 {
                    Button(showsAllQuotes ? "Show less" : "See all") {
                        withAnimation(.snappy(duration: 0.25)) {
                            showsAllQuotes.toggle()
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(.blueAccentText))
                    .buttonStyle(.plain)
                }
            }

            ClientThread(quotes: displayedQuotes, showsRail: false)
        }
    }

    // MARK: - Activity

    private struct ActivityEntry: Identifiable {
        let id: String
        let title: String
        let detail: String?
        let date: Date
        let tint: Color
    }

    private var activityEntries: [ActivityEntry] {
        var entries = client.quotes.prefix(3).map { quote in
            ActivityEntry(id: quote.id.uuidString,
                          title: activityTitle(for: quote.effectiveStatus),
                          detail: quote.displayTitle,
                          date: quote.createdAt,
                          tint: QuoteStatusStyle.text(quote.effectiveStatus))
        }
        if let first = client.quotes.min(by: { $0.createdAt < $1.createdAt }) {
            entries.append(ActivityEntry(id: "client-created",
                                         title: "Client created",
                                         detail: nil,
                                         date: first.createdAt,
                                         tint: Color(.statusMutedText)))
        }
        return entries
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Activity")

            VStack(spacing: 0) {
                ForEach(Array(activityEntries.enumerated()), id: \.element.id) { index, entry in
                    activityRow(entry, isLast: index == activityEntries.count - 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .shadow(color: cardShadow, radius: 12, y: 4)
        }
    }

    private func activityRow(_ entry: ActivityEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(entry.tint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 52)
                }
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                if let detail = entry.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(activityDateLabel(entry.date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, isLast ? 10 : 16)

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private func activityTitle(for status: String) -> String {
        switch status {
        case "viewed": return "Quote viewed"
        case "sent": return "Quote sent"
        case "accepted": return "Quote accepted"
        case "declined": return "Quote declined"
        case "expired": return "Quote expired"
        default: return "Quote created"
        }
    }

    private func activityDateLabel(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 86_400 { return quoteRelativeLabel(date) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Client information

    private var matchingVisits: [ScheduledVisit] {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return [] }
        return session.visitStore.visits
            .filter { $0.title.lowercased().contains(name) }
            .sorted { $0.date > $1.date }
    }

    private var clientPhone: String? {
        matchingVisits.compactMap { cleaned($0.phone) }.first
    }

    private var clientNotes: String? {
        matchingVisits.compactMap { cleaned($0.note) }.first
    }

    private var clientInformationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeading("Client information")
                Spacer()
                Button("Edit address") { editAddress() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(.blueAccentText))
                    .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                if let phone = clientPhone {
                    informationRow("Phone", value: phone)
                    Divider().padding(.leading, 16)
                }

                Button { showMap = true } label: {
                    informationRow("Address",
                                   value: location.address ?? location.suggestion ?? "Add an address",
                                   showsDisclosure: true)
                }
                .buttonStyle(.plain)

                if let notes = clientNotes {
                    Divider().padding(.leading, 16)
                    informationRow("Notes", value: notes)
                }
            }
            .background(Color(.cardSurface),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .shadow(color: cardShadow, radius: 12, y: 4)
        }
    }

    private func informationRow(_ label: String,
                                value: String,
                                showsDisclosure: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color(.mainText))
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(.rect)
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(.mainText))
    }
}
