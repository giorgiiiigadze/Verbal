//
//  LineItemsCard.swift
//  Verbal
//

import SwiftUI

/// The priced table, in a panel with its own header bar — the quote screen and
/// the recording review both use it, so the two can't drift apart again.
///
/// One fill throughout, and a divider to mark the heading.
///
/// It was two tones — a `surface` header over `cardSurface` rows — which is the
/// only tinted header bar in the app and made the table read as a spreadsheet
/// where the screen is trying to read as a document. It also barely existed:
/// those two colours are two levels apart in dark mode, so half the users were
/// already seeing the single fill this now commits to. `cardSurface`, not
/// `surface`, so the card lifts off the page like every other card rather than
/// sinking into it.
struct LineItemsCard<Rows: View>: View {
    /// Quote detail calls this “Line items”; onboarding uses the identical
    /// container to preview the rate card the person just created.
    var title = "Line items"
    /// Present only where the items can actually be edited — the recording
    /// review is showing a quote that hasn't been saved yet.
    var onExpand: (() -> Void)?
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Full weight and full colour. This introduces the prices, which
                // are the point of the document; as a grey footnote it was the
                // quietest label on a screen where it should be among the
                // loudest.
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Spacer()
                if let onExpand {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.down.left.and.arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            // The glyph is small; the tap target shouldn't be.
                            .frame(width: 30, height: 30)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit line items")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, onExpand == nil ? 10 : 6)
            .frame(maxWidth: .infinity)
            .background(Color(.cardSurface))

            // The only thing separating the heading from the table now, and
            // enough on its own: the title is already semibold in the main ink.
            Divider()

            VStack(spacing: 0) { rows }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.cardSurface))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}
