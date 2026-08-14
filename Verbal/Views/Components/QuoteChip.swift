//
//  QuoteChip.swift
//  Verbal
//

import SwiftUI

/// Small native rounded-rectangle chip with a leading icon/avatar and text.
struct QuoteChip<Leading: View>: View {
    let text: String
    /// Draws the chip in brand blue — used for an action still to be done,
    /// so it reads as inviting rather than as another piece of metadata.
    var tinted: Bool = false
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
                .font(.body)
                .foregroundStyle(tinted ? Color(.blueAccentText) : .secondary)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tinted ? Color(.blueAccentText) : Color(.mainText))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tinted ? Color(.royalBlue25) : Color(.surface), in: .capsule)
    }
}
