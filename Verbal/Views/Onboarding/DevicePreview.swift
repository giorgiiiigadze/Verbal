//
//  DevicePreview.swift
//  Verbal
//

import SwiftUI

/// All editable dimensions for the onboarding phone preview.
///
/// `displayedFrameWidth` is the main visual-size control. The remaining values
/// describe the source artwork and the full-size canvas used to compose the app
/// screen. Keeping them together makes future preview adjustments explicit and
/// avoids scattering unexplained numbers across three views.
enum OnboardingPhonePreviewMeasurements {
    /// Width of the complete phone on the opening onboarding screen.
    static let displayedFrameWidth: CGFloat = 292

    /// Logical iPhone canvas at which `OnboardingPhoneScreen` is composed
    /// before it is scaled into the frame's transparent opening.
    static let contentReferenceSize = CGSize(width: 393, height: 852)

    /// Pixel dimensions of `deviceFrame` in the asset catalog.
    static let frameArtworkSize = CGSize(width: 489, height: 1000)

    /// Height occupied by the phone at `displayedFrameWidth`.
    static var displayedFrameHeight: CGFloat {
        displayedFrameWidth * frameArtworkSize.height / frameArtworkSize.width
    }

    /// Pixel dimensions and origin of the transparent screen opening in that
    /// artwork. The opening starts at x: 25, y: 22.
    static let screenOpeningSize = CGSize(width: 438, height: 955)
    static let screenLeadingInset: CGFloat = 25
    static let screenTopInset: CGFloat = 22

    /// Corner radius of the glass as a fraction of its rendered width.
    static let screenCornerRadiusRatio: CGFloat = 0.135
}

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

    private typealias Measurements = OnboardingPhonePreviewMeasurements

    private static var imageAspect: CGFloat {
        Measurements.frameArtworkSize.width / Measurements.frameArtworkSize.height
    }
    private static var screenAspect: CGFloat {
        Measurements.screenOpeningSize.width / Measurements.screenOpeningSize.height
    }
    private static var leadingInset: CGFloat {
        Measurements.screenLeadingInset / Measurements.frameArtworkSize.width
    }
    private static var topInset: CGFloat {
        Measurements.screenTopInset / Measurements.frameArtworkSize.height
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width / Self.imageAspect
            let screenWidth = width * (1 - Self.leadingInset * 2)
            let screenHeight = screenWidth / Self.screenAspect

            ZStack {
                screen
                    .frame(width: screenWidth, height: screenHeight)
                    .clipShape(RoundedRectangle(
                        cornerRadius: screenWidth * Measurements.screenCornerRadiusRatio,
                        style: .continuous
                    ))
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
