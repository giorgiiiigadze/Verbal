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
}
