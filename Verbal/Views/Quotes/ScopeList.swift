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
                // Stepped back from the content it names. The facts in the
                // summary above are bold now, and a heading in full ink at the
                // same size read as another one of them — the darkest thing on
                // the page should be what the page says, not its labels.
                Text("Scope of work")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color(.mainText))
                                .frame(width: 7, height: 7)
                                // Centred on the first line's cap height rather
                                // than its box, so the dot sits with the text.
                                .padding(.top, 6)
                            // Regular, with the count semibold — see
                            // `emphasizedScopeItem`, which sets both. Medium
                            // throughout was what this and the summary once
                            // shared; the summary carries bold facts now, and
                            // five near-bold bullets under it outweighed the
                            // prose they belong to.
                            Text(emphasizedScopeItem(item))
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
