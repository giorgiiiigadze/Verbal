//
//  ClientMapSheet.swift
//  Verbal
//
//  Where this client is, full screen.
//
//  The one place in the app that fills the screen rather than taking a detent.
//  Every other sheet here asks a question and gets out of the way; this one is
//  the answer itself, and a map in 300 points is a map you immediately want to
//  make bigger.
//
//  Drawn the way Apple Maps draws itself — the map edge to edge under the
//  status bar, the controls floating on glass over it, and the detail on a card
//  at the bottom where the thumb is — because that is the shape the user is
//  already fluent in, and a map that looks like a map behaves like one.
//

import MapKit
import SwiftUI

struct ClientMapSheet: View {
    let clientName: String
    /// The client's address as the page has it. Owned above so it survives this
    /// sheet closing, and so an edit made here reaches the page behind it.
    let location: ClientLocation
    /// Opens the address editor on the page underneath — the alert lives there
    /// beside the rename it is modelled on, rather than being a second alert
    /// this sheet has to keep in sync.
    let onEditAddress: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var isHybrid = false

    private var address: String? { location.address }

    var body: some View {
        ZStack(alignment: .top) {
            map
            controls
        }
        .safeAreaInset(edge: .bottom) { card }
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - The map

    @ViewBuilder
    private var map: some View {
        if let coordinate = location.coordinate {
            Map(position: $camera) {
                Marker(clientName, systemImage: "house.fill", coordinate: coordinate)
                    .tint(Color(.royalBlue600))
            }
            .mapStyle(isHybrid ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
            .ignoresSafeArea()
            .onAppear { frame(on: coordinate) }
            .onChange(of: location.coordinate?.latitude) {
                if let coordinate = location.coordinate { frame(on: coordinate) }
            }
        } else {
            // No pin to draw, so the screen says why rather than showing an
            // ocean at zoom zero — the default region for a map with nothing
            // in it, and a screen the user would read as broken.
            emptyState
        }
    }

    /// Close enough to see the street, which is the question being asked. The
    /// span matches the visit preview's, so the two maps of one address in this
    /// app open at the same distance.
    private func frame(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.smooth(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            if location.isLoading {
                ProgressView()
                Text("Finding \(clientName)...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: location.hasAddress ? "mappin.slash" : "map")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color(.blueAccentText))
                Text(location.hasAddress
                     ? "We couldn't place this address on the map."
                     : "No address for \(clientName) yet.")
                    .font(.headline)
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)
                Text(location.hasAddress
                     ? "Directions will still search for it."
                     : "Add one and it'll be here on the morning of the visit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.homeBackground))
        .ignoresSafeArea()
    }

    // MARK: - Floating controls

    private var controls: some View {
        HStack {
            circleButton("xmark", label: "Close") { dismiss() }
            Spacer(minLength: 0)
            if location.coordinate != nil {
                circleButton(isHybrid ? "map.fill" : "globe.americas.fill",
                             label: isHybrid ? "Standard map" : "Satellite map") {
                    withAnimation(.snappy(duration: 0.2)) { isHybrid.toggle() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func circleButton(_ symbol: String,
                              label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.mainText))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - The card

    /// Who and where, then what to do about it. The same card shape the rest of
    /// the client page is built from, so the sheet reads as part of it.
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                InitialsAvatar(name: clientName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clientName)
                        .font(.robotoSlab(19, relativeTo: .headline))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text(address ?? "No address yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if let address {
                HStack(spacing: 10) {
                    primaryButton("Directions", symbol: "arrow.triangle.turn.up.right.diamond.fill") {
                        open(address, directions: true)
                    }
                    secondaryButton("Open in Maps") { open(address, directions: false) }
                }
                Button("Edit address") {
                    dismiss()
                    onEditAddress()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(.blueAccentText))
                .frame(maxWidth: .infinity)
            } else {
                primaryButton("Add address", symbol: "mappin.and.ellipse") {
                    dismiss()
                    onEditAddress()
                }
            }
        }
        .padding(16)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func primaryButton(_ title: String,
                               symbol: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(.royalBlue600),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color(.mainText))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(.fieldFill),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    /// Hands Apple Maps the place, not the sentence.
    ///
    /// An `MKMapItem` built on the coordinate already resolved opens on this
    /// exact pin; the `maps.apple.com?q=` URL used elsewhere makes Apple Maps
    /// search the string again and can land on a different building with a
    /// similar name. The URL is only the fallback for an address that never
    /// resolved — there is nothing better to hand over.
    private func open(_ address: String, directions: Bool) {
        if let coordinate = location.coordinate {
            let item = AddressGeocoder.mapItem(at: coordinate, address: address, named: clientName)
            item.openInMaps(launchOptions: directions
                            ? [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
                            : nil)
            return
        }
        let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?\(directions ? "daddr" : "q")=\(query)") else {
            return
        }
        UIApplication.shared.open(url)
    }
}
