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
    /// Closes the sheet. Also the caller's job, and for the same reason: with
    /// the card presented on top of this view, the local `dismiss` is refused —
    /// a sheet with a sheet of its own up cannot dismiss itself, so the X did
    /// nothing at all until this replaced it.
    let onClose: () -> Void
    @State private var camera: MapCameraPosition = .automatic
    @State private var isHybrid = false
    /// Flips the copy glyph to a tick once the address has been taken.
    @State private var copied = false
    /// How tall the card's content measures — see `detents`.
    @State private var expandedHeight: CGFloat = 0

    private var address: String? { location.address }

    private var coordinateKey: String? {
        guard let coordinate = location.coordinate else { return nil }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }

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
                        Button(role: .close, action: onClose)
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
                        .presentationDetents(detents)
                        // No `presentationBackground` on purpose. Overriding it
                        // with a colour is exactly what would replace the
                        // system's Liquid Glass with a flat panel.
                        .presentationDragIndicator(.visible)
                        // No `presentationCornerRadius`: the system's own is
                        // rounder than anything worth guessing at, and it is
                        // the radius every other sheet on the phone has.
                        // The map is the thing being looked at, so it stays
                        // live under the card rather than dimming behind it —
                        // and so do the toolbar buttons over it. Not
                        // `upThrough: .medium`: that names a detent this sheet
                        // no longer has, and with no match the interaction is
                        // off at every height, which is what left the close
                        // button ignoring taps.
                        .presentationBackgroundInteraction(.enabled)
                        .interactiveDismissDisabled()
                }
        }
        .presentationBackground(Color(.systemBackground))
    }

    /// The resting height: who they are and the two actions, and nothing more.
    /// The point of the sheet is the map behind it.
    private let collapsedHeight: CGFloat = 148

    /// Where the sheet stops when pulled up.
    ///
    /// Measured from the content rather than set to `.medium`, which is what
    /// left half a screen of empty glass under the last row: how tall this card
    /// wants to be depends on whether there is an address, a booked visit, or
    /// neither, and only the content knows.
    private var detents: Set<PresentationDetent> {
        guard expandedHeight > 0 else { return [.height(collapsedHeight)] }
        // Too close to the resting height to be worth dragging to — the whole
        // card already fits, so offer the one height that shows all of it.
        guard expandedHeight > collapsedHeight + 44 else {
            return [.height(expandedHeight)]
        }
        return [.height(collapsedHeight), .height(expandedHeight)]
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
            // The system compass uses the same top-right corner as the map style
            // toggle once the map is rotated, so keep this sheet's controls to
            // the explicit chrome it draws itself.
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
            .onAppear { frame(on: coordinate) }
            .onChange(of: coordinateKey) {
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
        ZStack {
            Color(.homeBackground)
                .ignoresSafeArea()

            if location.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Finding \(clientName)...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
            } else {
                EmptyStateMessage(
                    icon: location.hasAddress ? "mappin.slash" : "map",
                    title: location.hasAddress ? "Address not found" : "No address yet",
                    message: location.hasAddress
                    ? "Directions will still search for it."
                    : "Add one and it'll be here on the morning of the visit."
                ) {
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The card

    /// Who and where, what to do about it, then the detail.
    ///
    /// Laid out the way a place card is: the identity and the two actions sit
    /// above the fold at the resting detent, and everything else is reached by
    /// pulling the sheet up. That is also what fixes the empty half — the
    /// expanded sheet now has something to expand *to*, rather than growing a
    /// blank area under three controls.
    ///
    /// No background of its own: the sheet it lives in is already Liquid Glass,
    /// and a filled card drawn inside would sit on the glass as a second
    /// surface rather than being one.
    private var card: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identity
                    actions
                    if address != nil { details }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // The detent has to clear the home indicator too, and is
                    // capped so a long address can't push the card over the map
                    // it is describing.
                    expandedHeight = min(height + proxy.safeAreaInsets.bottom, 620)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var identity: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: clientName, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(clientName)
                    .font(.robotoSlab(21, relativeTo: .title3))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
                Text(address ?? "No address yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let address {
            HStack(spacing: 10) {
                Button {
                    open(address, directions: true)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                // The platform's own glass, tinted — the hand-built rectangle
                // this replaces couldn't pick up what was behind it, which on
                // glass is the whole point.
                .buttonStyle(.glassProminent)
                .tint(Color(.mapAction))

                Button {
                    open(address, directions: false)
                } label: {
                    Text("Open in Maps")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.mapAction))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                // The same blue at 16%, so the second action reads as the
                // quieter half of a pair rather than as a different colour.
                .buttonStyle(.glass)
                .tint(Color(.mapAction).opacity(0.16))
            }
            .controlSize(.large)
        } else {
            Button(action: onEditAddress) {
                Label("Add address", systemImage: "mappin.and.ellipse")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(.mapAction))
            .controlSize(.large)
        }
    }

    // MARK: - Details

    /// The rows under the fold. Plain rows on hairlines rather than a filled
    /// group: the glass is the surface, and a card inside it would be a second.
    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Details")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            if let address {
                detailRow("mappin", "Address", address) {
                    UIPasteboard.general.string = address
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = true
                } trailing: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.mapAction))
                        .contentTransition(.symbolEffect(.replace))
                }
            }

            if let visit = location.nextVisit {
                Divider()
                detailRow("calendar", "Next visit", visit.whenText)
            }

            Divider()
            detailRow("mappin.and.ellipse", "Edit address",
                      location.hasAddress ? "Change where they are" : "Add one",
                      action: onEditAddress)
        }
    }

    private func detailRow<Trailing: View>(_ symbol: String,
                                           _ label: String,
                                           _ value: String,
                                           action: (() -> Void)? = nil,
                                           @ViewBuilder trailing: () -> Trailing = { EmptyView() })
    -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.mapAction))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Color(.mainText))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
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
