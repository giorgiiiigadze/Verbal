//
//  LocationSearchView.swift
//  Verbal
//

import Combine
import MapKit
import SwiftUI

/// Apple Maps' type-ahead results, kept separate from the screen so the same
/// picker can later be used for a client's saved address.
@MainActor
private final class LocationSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

/// A small, device-local history. These are locations selected deliberately,
/// never every partial phrase someone types into the search field.
private enum RecentLocations {
    private static let key = "recent-location-searches"
    private static let maximumCount = 8

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ location: String) {
        let clean = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let locations = all.filter { $0.localizedCaseInsensitiveCompare(clean) != .orderedSame }
        UserDefaults.standard.set(Array(([clean] + locations).prefix(maximumCount)), forKey: key)
    }
}

/// A destination in the booking sheet's navigation stack, rather than another
/// modal layer. Selecting a Maps result immediately takes the user back to the
/// booking details with the formatted address in place.
struct LocationSearchView: View {
    @Binding var address: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = LocationSearch()
    @State private var recents = RecentLocations.all

    private var trimmedQuery: String {
        search.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        content
        .background(Color(.homeBackground))
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Add location")
    }

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty, recents.isEmpty {
            EmptyStateMessage(
                icon: "mappin.and.ellipse",
                assetIcon: "LocationPin",
                assetIconSize: 42,
                title: "No recent locations",
                message: "Search for a place and selected locations will be saved here."
            ) {
                EmptyView()
            }
        } else if !trimmedQuery.isEmpty, search.results.isEmpty {
            EmptyStateMessage(
                icon: "magnifyingglass",
                assetIcon: "VisitsNoMatches",
                title: "No locations found",
                message: "No locations match “\(trimmedQuery)”."
            ) {
                EmptyView()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if trimmedQuery.isEmpty {
                        recentLocations
                    } else {
                        suggestions
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var recentLocations: some View {
        sectionTitle("Recents")
        ForEach(recents, id: \.self) { location in
            Button { choose(location) } label: {
                locationRow(title: locationTitle(for: location),
                            subtitle: locationSubtitle(for: location))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        sectionTitle("Suggestions")
        ForEach(search.results, id: \.self) { result in
            Button { choose(locationText(for: result)) } label: {
                locationRow(title: result.title,
                            subtitle: result.subtitle)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .padding(.top, 28)
            .padding(.bottom, 16)
    }

    private func locationRow(title: String, subtitle: String?) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Image("LocationPin")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 20, height: 24)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func locationTitle(for location: String) -> String {
        location.split(separator: ",", maxSplits: 1).first.map(String.init) ?? location
    }

    private func locationSubtitle(for location: String) -> String? {
        let parts = location.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[1]).trimmingCharacters(in: .whitespaces)
    }

    private func choose(_ location: String) {
        address = location
        RecentLocations.record(location)
        recents = RecentLocations.all
        dismiss()
    }

    private func locationText(for result: MKLocalSearchCompletion) -> String {
        result.subtitle.isEmpty ? result.title : "\(result.title), \(result.subtitle)"
    }
}
