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
