//
//  ScopeList.swift
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
