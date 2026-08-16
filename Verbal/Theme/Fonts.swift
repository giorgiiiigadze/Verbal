//
//  Fonts.swift
//  Verbal
//

import SwiftUI

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
}
