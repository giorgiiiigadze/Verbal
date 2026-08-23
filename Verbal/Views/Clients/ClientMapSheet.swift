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
//  status bar, the controls floating on glass over it, and the detail on a
//  card at the bottom where the thumb is — because that is the shape the user
//  is already fluent in, and a map that looks like a map behaves like one.
//
//  That card is a sheet of its own rather than an inset view, which is what
//  buys it the platform's Liquid Glass, its grabber, its detents, and a map
//  that keeps panning underneath while it is up. Drawing a rounded rectangle
//  that resembles one gets the picture and none of the behaviour.
//

import MapKit
import SwiftUI

struct ClientMapSheet: View {
    let clientName: String
    /// The client's address as the page has it. Owned above so it survives this
    /// sheet closing, and so an edit made here reaches the page behind it.
    let location: ClientLocation
    /// Closes this sheet and opens the address editor on the page underneath.
    /// The alert lives there, beside the rename it is modelled on, rather than
    /// being a second alert this sheet has to keep in sync — and dismissing is
    /// the caller's job now that the card is a sheet inside a sheet, where the
    /// local `dismiss` would only close the card.
    let onEditAddress: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var isHybrid = false

    private var address: String? { location.address }

    var body: some View {
        NavigationStack {
            map
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                // The bar itself goes, the buttons stay. What is left is two
                // pieces of Liquid Glass floating on the map — which is both
                // what Apple Maps does and the only way a header works here:
                // a solid bar would slice the top off the thing being looked at.
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        // The system close button, not an `xmark` drawn to look
                        // like one: the role is what gets it the platform's own
                        // glass, its size, and its VoiceOver label.
                        Button(role: .close) { dismiss() }
                    }
                    if location.coordinate != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { isHybrid.toggle() }
                            } label: {
                                Image(systemName: isHybrid ? "map.fill" : "globe.americas.fill")
                            }
                            .accessibilityLabel(isHybrid ? "Standard map" : "Satellite map")
                        }
                    }
                }
                // Always up, never dismissable: it is the sheet's content, not
                // something the user opened on top of it. `.constant(true)` is
                // what says so — there is no state that could close it.
                .sheet(isPresented: .constant(true)) {
                    card
                        .presentationDetents([.height(cardHeight), .medium])
                        // No `presentationBackground` on purpose. Overriding it
                        // with a colour is exactly what would replace the
                        // system's Liquid Glass with a flat panel.
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(28)
                        // The map is the thing being looked at, so it stays
                        // live under the card rather than dimming behind it.
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        .interactiveDismissDisabled()
                }
        }
        .presentationBackground(Color(.systemBackground))
    }

    /// Tall enough for the client, their address and the buttons, and no
    /// taller — the resting detent should leave as much map showing as it can.
    private var cardHeight: CGFloat { address == nil ? 150 : 205 }

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

    // MARK: - The card

    /// Who and where, then what to do about it.
    ///
    /// No background of its own: the sheet it lives in is already Liquid Glass,
    /// and a filled card drawn inside would sit on the glass as a second
    /// surface rather than being one.
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                InitialsAvatar(name: clientName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clientName)
                        .font(.robotoSlab(20, relativeTo: .title3))
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
                    Button {
                        open(address, directions: true)
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                    }
                    // The platform's own glass, prominent and tinted — the
                    // hand-built royal-blue rectangle this replaces couldn't
                    // pick up what was behind it, which on glass is the whole
                    // point.
                    .buttonStyle(.glassProminent)
                    .tint(Color(.royalBlue600))

                    Button {
                        open(address, directions: false)
                    } label: {
                        Text("Open in Maps")
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)

                Button("Edit address", action: onEditAddress)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(.blueAccentText))
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: onEditAddress) {
                    Label("Add address", systemImage: "mappin.and.ellipse")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                }
                .buttonStyle(.glassProminent)
                .tint(Color(.royalBlue600))
                .controlSize(.large)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
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
