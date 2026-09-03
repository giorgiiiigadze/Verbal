//
//  ScopeList.swift
//  Verbal
//

import SwiftUI

/// Client-facing "Scope of work" — a titled bullet list of what the job covers.
/// Renders nothing when empty. Shown between the summary and the line-items table.
/// The document body face — serif, a step larger than `.body`. Shared by the
/// summary, the scope bullets and the Terms/Notes footer so the quote reads in
/// one voice rather than as three differently-set blocks.
extension Font {
    static let quoteDocumentBody = Font.system(size: 18, design: .serif)
    /// Section headings in the same serif, a step up and in full ink. The
    /// small grey label this page used before named a section without giving
    /// it any weight; a heading should be able to hold its own block.
    static let quoteDocumentHeading = Font.system(size: 20, weight: .semibold, design: .serif)
}

struct ScopeList: View {
    let items: [String]
    /// The document look — serif body at a larger size, a serif heading in
    /// full ink, and wider bullets. Opt-in so the recording review and
    /// onboarding, which share this view, keep the layout they have.
    var documentStyle: Bool = false

    var body: some View {
        if !items.isEmpty {
            // 8 under the heading, against the 32 above it. Space belongs above
            // a heading, not below: it should read as attached to what follows
            // rather than floating between two blocks.
            VStack(alignment: .leading, spacing: 8) {
                // Two readings of the same heading. The grey label steps back
                // from the content it names, which is right where the block is
                // one of several in a review screen. On the quote itself the
                // section is the unit the eye lands on, so it is set in the
                // body serif a size up and in full ink.
                if documentStyle {
                    Text("Scope of work")
                        .font(.quoteDocumentHeading)
                        .foregroundStyle(Color(.mainText))
                        .padding(.bottom, 2)
                } else {
                    Text("Scope of work")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: documentStyle ? 18 : 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: documentStyle ? 14 : 10) {
                            Circle()
                                .fill(Color(.mainText))
                                .frame(width: documentStyle ? 6 : 7,
                                       height: documentStyle ? 6 : 7)
                                // Centred on the first line's cap height rather
                                // than its box, so the dot sits with the text.
                                .padding(.top, documentStyle ? 9 : 6)
                            // Regular, with the count semibold — see
                            // `emphasizedScopeItem`, which sets both. Medium
                            // throughout was what this and the summary once
                            // shared; the summary carries bold facts now, and
                            // five near-bold bullets under it outweighed the
                            // prose they belong to.
                            Text(emphasizedScopeItem(item))
                                .font(documentStyle ? .quoteDocumentBody : nil)
                                .lineSpacing(documentStyle ? 8 : 0)
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
                .padding(.leading, documentStyle ? 8 : 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
