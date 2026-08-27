//
//  EmptyStateMessage.swift
//  Verbal
//
//  What a screen says when it has nothing on it and no explaining to do.
//
//  Distinct from the first-run cards on Home and the rate card, which have a
//  product to introduce and earn their tinted panels and sample rows. This is
//  for the user who already knows what the screen is: they emptied it, or they
//  have not filled it yet today. Nothing is being sold, so nothing is raised —
//  a quiet glyph, a line, and the way back offered rather than pressed.
//
//  Shared so the two screens can't drift into two dialects of the same
//  sentence.
//

import SwiftUI

struct EmptyStateMessage<Actions: View>: View {
    /// An SF Symbol, drawn light. Unfilled where the tab bar shows the filled
    /// version of the same glyph, so it reads as that thing with nothing in it.
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(Color(.mainText))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 44)
                .padding(.top, 6)

            VStack(spacing: 10) { actions }
                .padding(.top, 22)

            Spacer(minLength: 0)
            // Twice below, so the block settles above the middle rather than in
            // it — dead centre on a tall screen reads as floating.
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

/// A quiet capsule action: icon, label, and a chevron to say it goes somewhere.
///
/// Deliberately not the blue filled button. On Home the primary Record action
/// already floats nearby, so a second solid button would make identical actions
/// look like a decision the user has to make.
struct EmptyStatePill: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                // The same ink as the label. In blue it was the loudest thing on
                // a screen built to be quiet, and it set the glyph apart from
                // the words it belongs to — they are one phrase, not a mark
                // beside a caption.
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(.cardSurface), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
