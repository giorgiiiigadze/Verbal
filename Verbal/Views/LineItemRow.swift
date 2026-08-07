//
//  LineItemRow.swift
//  Verbal
//

import SwiftUI

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
                                .frame(width: 6, height: 6)
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
                .padding(.leading, 18)
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
