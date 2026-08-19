//
//  CardPressStyle.swift
//  Verbal
//
//  The press state a rate card uses, so the highlight lands on the card's own
//  shape rather than the list row behind it.
//

import SwiftUI

/// Presses the card rather than the row it sits in. A bare tap gesture leaves
/// the List to draw its own highlight, which runs the full width of the row and
/// squares off the corners the card was drawn with — so the feedback lands on a
/// shape the user can't see. Matches how a quote row behaves.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
