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
    /// A colour of the chip's own, overriding both defaults above.
    ///
    /// Only the status chip uses this, and it passes `QuoteStatusStyle` — the
    /// same pair the list row's pill wears, so a quote is the same colour
    /// wherever its state is named. A pair rather than one tint because the
    /// ink and the ground are chosen together.
    var palette: (text: Color, fill: Color)? = nil
    @ViewBuilder let leading: Leading

    private var foreground: Color {
        if let palette { return palette.text }
        return tinted ? Color(.blueAccentText) : Color(.mainText)
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
                .font(.body)
                // The icon reads a step quieter than the label on a plain chip.
                // On a coloured one it takes the label's colour: the pair was
                // chosen to sit together, and a grey glyph in the middle of it
                // looks like a mistake.
                .foregroundStyle(palette == nil && !tinted ? .secondary : foreground)
                // For the one chip whose glyph changes in place — status. The
                // others hold a constant symbol, so nothing else moves.
                .contentTransition(.symbolEffect(.replace))
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(foreground)
                // Crossfades with the fill behind it. Cut against a colour that
                // fades, the label read as a different chip appearing rather
                // than as this one changing.
                .contentTransition(.opacity)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette?.fill ?? (tinted ? Color(.royalBlue25) : Color(.surface)),
                    in: .capsule)
    }
}
