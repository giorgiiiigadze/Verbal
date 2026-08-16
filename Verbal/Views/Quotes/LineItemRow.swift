//
//  LineItemRow.swift
//  Verbal
//

import SwiftUI

/// One row in a quote's line-item table. Reused by the recording review and detail pages.
struct LineItemRow: View {
    let description: String
    let quantityText: String?
    let isMissingPrice: Bool
    let lineTotal: Double?
    /// The quote's own currency; nil falls back to the current setting (used
    /// while building a new quote that isn't saved yet).
    var currencyCode: String? = nil
    /// The model's own read on whether it heard this line right — "high" or
    /// "low". Nil on lines the user typed, and on anything saved before the
    /// field was persisted, so absence means "nothing to say" rather than
    /// "fine".
    var confidence: String? = nil

    /// The one warning colour, shared with everything that flags an unpriced or
    /// low-confidence line — the rate card, the recording review and the list
    /// pill all read it off here so the mark is the same amber everywhere.
    ///
    /// An asset rather than the fixed RGB it was, so it finally lightens in the
    /// dark instead of staying the same deep orange against a dark card. The
    /// light value is unchanged.
    static let amber = Color(.statusWarningText)

    /// Compared as a string because that is what the column holds. Anything
    /// other than "low" — "high", nil, a value the model invents later — says
    /// nothing, which is the safe direction to fail in: a quiet row is the
    /// normal one.
    private var isLowConfidence: Bool { confidence == "low" }

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
                // Under the quantity rather than opposite the price, because
                // the trailing slot is already spoken for and this is a remark
                // about the numbers on the left.
                //
                // Silent on a line with no price: "Needs price" is the louder
                // and more actionable of the two, and a row wearing both amber
                // marks says one thing twice. A missing price is also the case
                // the user can already see is wrong — a misheard one isn't.
                if isLowConfidence, !isMissingPrice {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Self.amber)
                            .frame(width: 5, height: 5)
                        Text("Worth checking")
                            .font(.caption)
                            .foregroundStyle(Self.amber)
                    }
                    .padding(.top, 1)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Worth checking — the app wasn't sure it heard this line correctly")
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
                RollingAmount(value: lineTotal, code: currencyCode)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
            }
        }
        .padding(.vertical, 14)
    }
}
