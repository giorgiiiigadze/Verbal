//
//  Fonts.swift
//  Verbal
//

import SwiftUI
import UIKit

extension Font {
    /// Roboto Slab — the app's primary custom font.
    /// Scales with Dynamic Type via `relativeTo`.
    static func robotoSlab(_ size: CGFloat, relativeTo textStyle: TextStyle = .body) -> Font {
        .custom("RobotoSlab-Regular", size: size, relativeTo: textStyle)
    }

    /// Roboto Slab at a size Dynamic Type cannot move.
    ///
    /// For text inside a shape that can't grow with it — the initials in an
    /// avatar circle. Scaled, the letters run past the edge of a circle whose
    /// diameter is a fixed number of points.
    static func robotoSlabFixed(_ size: CGFloat) -> Font {
        .custom("RobotoSlab-Regular", fixedSize: size)
    }

    /// The system font at a point size that grows with Dynamic Type.
    ///
    /// `Font.system(size:)` is frozen — the number is the number, whatever the
    /// user has asked for in Settings. That is right for the PDF, where a point
    /// is a point on a printed page, and wrong everywhere else: it left the
    /// app's headings stuck at their design size while the body text around
    /// them grew, so turning text up made the hierarchy invert.
    ///
    /// Sizes are unchanged at the default text size — this scales from the
    /// design's own number rather than snapping to the nearest text style, so
    /// nothing moves for the majority of users who never touch the setting.
    static func scaledSystem(
        _ size: CGFloat,
        relativeTo textStyle: TextStyle = .body,
        weight: Weight = .regular,
        design: Design = .default
    ) -> Font {
        .system(size: UIFontMetrics(forTextStyle: textStyle.uiTextStyle).scaledValue(for: size),
                weight: weight,
                design: design)
    }
}

private extension Font.TextStyle {
    /// The UIKit twin, so `UIFontMetrics` can be asked to do the scaling.
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
