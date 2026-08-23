//
//  ClientLocation.swift
//  Verbal
//
//  Where a client is, and how the app turns that sentence into a pin.
//
//  Two jobs that only look like one. `AddressGeocoder` is the shared answer to
//  "what are the coordinates of this text" — it was written once for the visit
//  sheet and is now asked the same question by the client map, so it lives here
//  rather than in either screen. `ClientLocation` is the client's own address:
//  fetched from the customer row, kept for as long as the page is up, and
//  resolved through the geocoder.
//
//  Neither touches CoreLocation. Geocoding an address needs no permission, and
//  the app has never asked for one — a map of somebody else's house has no use
//  for where the phone is standing.
//

import MapKit
import SwiftUI

// MARK: - Geocoding

/// Text to a coordinate, with the wait built in.
enum AddressGeocoder {
    /// How long to sit on a keystroke before spending a lookup on it. Long
    /// enough that typing an address is one request rather than thirty.
    static let typingDelay = Duration.milliseconds(450)

    /// The coordinate for an address, or nil if Apple can't place it.
    ///
    /// Throwing is deliberately not how "couldn't find it" is reported: an
    /// unplaceable address is an ordinary outcome here, not an error the caller
    /// should show a failure for. A genuine failure comes back as nil too — the
    /// screens above treat both the same way, by keeping the address and
    /// dropping the pin.
    static func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let request = MKGeocodingRequest(addressString: query) else {
            return nil
        }
        return try? await request.mapItems.first?.location.coordinate
    }

    /// A place Apple Maps can be opened *on*, rather than a string it has to
    /// search for again.
    ///
    /// Built from `MKAddress` rather than the `MKPlacemark` this used to use —
    /// placemarks are deprecated as of iOS 26. The client's name goes in as the
    /// short address, which is the label Maps puts under the pin.
    static func mapItem(at coordinate: CLLocationCoordinate2D,
                        address: String,
                        named name: String) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude,
                                                  longitude: coordinate.longitude),
                             address: MKAddress(fullAddress: address, shortAddress: name))
        // Without this the destination reads "Unknown Location" in Apple Maps:
        // an item built from a bare coordinate has no name of its own, and the
        // address alone doesn't become one.
        item.name = name
        return item
    }
}

// MARK: - A client's address

/// The address of one client, and the pin it resolves to.
///
/// Observable and owned by `ClientDetailView` rather than by the map sheet, so
/// the address survives the sheet being closed and reopened — the second look
/// at the map is instant, and editing the address updates the page behind it.
@MainActor
@Observable
final class ClientLocation {
    /// The address on the customer row. Nil until loaded, and nil after loading
    /// when they have never been given one.
    private(set) var address: String?
    /// An address the app can see but hasn't been told to keep: taken from a
    /// visit already booked with this client. Offered as the starting text in
    /// the editor, never saved on their behalf — an address is a fact about a
    /// person, and inferring one from a job title is a guess.
    private(set) var suggestion: String?
    private(set) var coordinate: CLLocationCoordinate2D?
    /// The soonest visit booked with this client, if any. Read at the same time
    /// as the address and from the same list — the map is where "when am I next
    /// due there" is worth answering, and the page behind it doesn't ask it.
    private(set) var nextVisit: ScheduledVisit?
    /// True from the first fetch until there is something to draw, so the sheet
    /// can show a spinner instead of flashing its empty state at a client who
    /// does have an address.
    private(set) var isLoading = false

    /// Whose address this is, case-folded — the same identity `Client.id` uses.
    private var loadedKey: String?

    var hasAddress: Bool { address?.isEmpty == false }

    /// What the editor should open with: their address, or the visit's if they
    /// have none of their own.
    var editingText: String { address ?? suggestion ?? "" }

    /// Fetch the address for a client and place it. Cheap to call again with
    /// the same person — it returns without a request.
    func load(name: String, key: String) async {
        guard loadedKey != key else { return }
        loadedKey = key
        isLoading = true
        let booked = Self.visits(for: name)
        suggestion = Self.address(from: booked)
        nextVisit = booked.first { $0.date >= Date() }

        let fetched = try? await QuoteService.customerAddress(named: name)
        // A rename mid-flight moves the page to somebody else; the answer to
        // the old question must not land on the new person.
        guard loadedKey == key else { return }
        address = fetched
        await resolve()
        isLoading = false
    }

    /// Write a new address, moving the page onto it first so the map redraws
    /// under the thumb rather than after the round trip.
    func save(_ newAddress: String, name: String) async throws {
        let trimmed = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = address
        address = trimmed.isEmpty ? nil : trimmed
        await resolve()
        do {
            try await QuoteService.setCustomerAddress(trimmed, forClientNamed: name)
        } catch {
            address = previous
            await resolve()
            throw error
        }
    }

    /// Called when the page follows a rename, so the next open asks about the
    /// person it is now showing.
    func invalidate() {
        loadedKey = nil
        address = nil
        suggestion = nil
        coordinate = nil
        nextVisit = nil
    }

    private func resolve() async {
        guard let address, !address.isEmpty else {
            coordinate = nil
            return
        }
        let found = await AddressGeocoder.coordinate(for: address)
        // Only accept the answer if it is still the answer to the current
        // address — a quick correction can land two lookups out of order.
        guard self.address == address else { return }
        coordinate = found
    }

    /// Visits booked with this client, soonest first.
    ///
    /// Visits carry one free-text title — "Mrs. Patel — bathroom" — so the
    /// match is a containment check on the name rather than a lookup. Loose on
    /// purpose: the worst case is that the editor opens pre-filled with an
    /// address the user then clears, and the best case is that they never type
    /// an address they already typed once.
    private static func visits(for name: String) -> [ScheduledVisit] {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return ScheduledVisit.load()
            .filter { $0.title.lowercased().contains(needle) }
            .sorted { $0.date < $1.date }
    }

    /// The address off the most recently booked of them — the latest one is the
    /// most likely to still be where they live.
    private static func address(from visits: [ScheduledVisit]) -> String? {
        visits
            .compactMap { $0.address?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty }
    }
}
