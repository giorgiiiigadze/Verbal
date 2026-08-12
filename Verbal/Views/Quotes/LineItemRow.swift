//
//  LineItemRow.swift
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
                Text("Line items")
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

/// Client-facing "Scope of work" — a titled bullet list of what the job covers.
/// Renders nothing when empty. Shown between the summary and the line-items table.
struct ScopeList: View {
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            // 8 under the heading, against the 32 above it. Space belongs above
            // a heading, not below: it should read as attached to what follows
            // rather than floating between two blocks.
            VStack(alignment: .leading, spacing: 8) {
                Text("Scope of work")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color(.mainText))
                                .frame(width: 7, height: 7)
                                // Centred on the first line's cap height rather
                                // than its box, so the dot sits with the text.
                                .padding(.top, 7)
                            // The same weight as the summary above it. These are
                            // two halves of one description of the job and were
                            // set as though one mattered more.
                            Text(item)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(Color(.mainText))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // 4, not 18. The bullets used to start 18pt in from their own
                // heading, so the scope's text ran down a different left edge
                // to the summary's — two columns on a page that has one. The
                // dots now sit just off the margin and only the text hangs,
                // which is what makes a list read as part of the prose rather
                // than as something pasted beside it.
                .padding(.leading, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One row in a quote's line-item table. Reused by the recording review and detail pages.
struct LineItemRow: View {
    let description: String
    let quantityText: String?
    let isMissingPrice: Bool
    let lineTotal: Double?
    /// The quote's own currency; nil falls back to the current setting (used
    /// while building a new quote that isn't saved yet).
    var currencyCode: String? = nil

    static let amber = Color(red: 217 / 255, green: 115 / 255, blue: 13 / 255)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(description)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                if let quantityText {
                    Text(quantityText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isMissingPrice {
                HStack(spacing: 6) {
                    Circle().fill(Self.amber).frame(width: 7, height: 7)
                    Text("Needs price")
                        .font(.footnote)
                        .foregroundStyle(Self.amber)
                }
            } else if let lineTotal {
                Text(lineTotal, format: AppCurrency.format(code: currencyCode))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
            }
        }
        .padding(.vertical, 14)
    }
}
