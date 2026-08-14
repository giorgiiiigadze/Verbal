//
//  DevicePreview.swift
//  Verbal
//

import SwiftUI

/// Apple's own iPhone artwork, with whatever is given to it showing through the
/// screen.
///
/// The frame was drawn by hand first — a bezel, a rounded rect and an island —
/// which was content-agnostic but never quite looked like the thing it was
/// imitating. This is the real geometry, exported with the screen left
/// transparent, so the content sits underneath and the bezel lies over it.
///
/// Every number below was measured off the file rather than guessed. They are
/// fractions, not points, so the frame can be drawn at any size and the screen
/// still lands exactly inside the glass.
struct DevicePreview<Screen: View>: View {
    @ViewBuilder var screen: Screen

    /// Measured from the 489 × 1000 export: the transparent screen runs from
    /// x 25–463 and y 22–977.
    private static var imageAspect: CGFloat { 489.0 / 1000.0 }
    private static var screenAspect: CGFloat { 438.0 / 955.0 }
    private static var leadingInset: CGFloat { 25.0 / 489.0 }
    private static var topInset: CGFloat { 22.0 / 1000.0 }
    /// The corner radius of the glass itself, as a share of the screen's width.
    private static var screenRadius: CGFloat { 0.135 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width / Self.imageAspect
            let screenWidth = width * (1 - Self.leadingInset * 2)
            let screenHeight = screenWidth / Self.screenAspect

            ZStack {
                screen
                    .frame(width: screenWidth, height: screenHeight)
                    .clipShape(RoundedRectangle(cornerRadius: screenWidth * Self.screenRadius,
                                                style: .continuous))
                    .position(x: width / 2,
                              y: height * Self.topInset + screenHeight / 2)

                Image(.deviceFrame)
                    .resizable()
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(Self.imageAspect, contentMode: .fit)
    }
}
