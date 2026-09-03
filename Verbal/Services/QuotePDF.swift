//
//  QuotePDF.swift
//  Verbal
//
//  Renders a quote to a PDF file the user can send to a client.
//

import SwiftUI
import UIKit

enum QuotePDF {
    /// Hard caps on line items per page, kept as a backstop for the height
    /// estimate below. A page can hold fewer than these; it must never hold
    /// more.
    private static let itemsOnFirstPage = 9
    private static let itemsOnLaterPages = 20

    /// Render `document` to a PDF in the temporary directory and return its URL.
    /// Runs on the main actor because it rasterizes SwiftUI views.
    @MainActor
    static func write(_ document: QuoteDocument) throws -> URL {
        let scale = singlePageScale(document)
        let pages = scale == nil ? paginate(document) : [document.lineItems]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.fileName)
        // A previous export with the same name would otherwise linger.
        try? FileManager.default.removeItem(at: url)

        var mediaBox = CGRect(x: 0, y: 0, width: PageMetrics.width, height: PageMetrics.height)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw PDFError.couldNotCreateContext
        }

        for (index, items) in pages.enumerated() {
            let page = QuoteDocumentPage(
                document: document,
                items: items,
                isFirstPage: index == 0,
                isLastPage: index == pages.count - 1,
                pageNumber: index + 1,
                pageCount: pages.count,
                contentScale: scale ?? 1
            )
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(width: PageMetrics.width,
                                                     height: PageMetrics.height)
            // Deliberately left at the default scale: text and shapes draw into
            // the PDF as vectors, so they stay sharp at any zoom, and raising
            // the scale here would enlarge the drawing rather than sharpen it.
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }

        context.closePDF()
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        return url
    }

    /// Split line items across pages, filling each one until the space runs out.
    ///
    /// This used to be a fixed nine items on the first page and twenty after,
    /// which held only for an average quote. Everything above the table on page
    /// one — the logo, the contact lines, the summary, the scope — is as tall as
    /// the user's own words, and the page frame does not clip: content that
    /// doesn't fit is simply drawn past the edge of the PDF's page box and lost.
    /// A quote with a long summary and six scope bullets silently posted a line
    /// item off the bottom of the document a client was about to read.
    ///
    /// The heights below are estimates, and deliberately generous — every one
    /// errs towards making a page hold less. A short page looks fine; an
    /// overflowing one looks broken.
    /// How much the whole quote has to shrink to land on one page, or nil when
    /// it is too long to be worth trying.
    ///
    /// A quote that overruns by a few percent used to split, which left the
    /// first page with the rows and a hand-sized hole where the totals had been
    /// — the reader sees an unfinished page, not a full one. Setting the type a
    /// touch smaller keeps it whole. Past `maxShrink` it genuinely is two pages'
    /// worth of quote and it splits properly.
    private static func singlePageScale(_ document: QuoteDocument) -> CGFloat? {
        let available = PageMetrics.height - PageMetrics.margin * 2 - Layout.footer
        let needed = headerHeight(document)
            + Layout.tableHeader
            + document.lineItems.reduce(0) { $0 + rowHeight($1) }
            + tailHeight(document)
        guard needed > available else { return 1 }
        let scale = available / needed
        return scale >= maxShrink ? scale : nil
    }

    /// The smallest the document may be set. 0.86 takes 11pt body text to a
    /// shade over 9 — still comfortably readable in print, and about as far as
    /// a page can be squeezed before it looks squeezed.
    private static let maxShrink: CGFloat = 0.86

    private static func paginate(_ document: QuoteDocument) -> [[QuoteLineItem]] {
        let items = document.lineItems
        guard !items.isEmpty else { return [[]] }

        let first = pageBudget - headerHeight(document)
        var pages: [[QuoteLineItem]] = []
        var current: [QuoteLineItem] = []
        var used: CGFloat = 0
        var budget = first
        var cap = itemsOnFirstPage

        for item in items {
            let height = rowHeight(item)
            if !current.isEmpty && (used + height > budget || current.count >= cap) {
                pages.append(current)
                current = []
                used = 0
                budget = pageBudget
                cap = itemsOnLaterPages
            }
            current.append(item)
            used += height
        }
        pages.append(current)

        // The last page carries the totals, any terms and notes, and the
        // acceptance line. Reserving that on every page would push small quotes
        // onto a second sheet for no reason, so it is settled here: if the tail
        // doesn't fit under the rows that landed on the last page, rows move to
        // a new one until it does.
        let tail = tailHeight(document)
        let lastBudget = pages.count == 1 ? first : pageBudget
        var lastUsed = pages[pages.count - 1].reduce(0) { $0 + rowHeight($1) }
        var moved: [QuoteLineItem] = []
        while lastUsed + tail > lastBudget, let row = pages[pages.count - 1].popLast() {
            lastUsed -= rowHeight(row)
            moved.insert(row, at: 0)
        }
        if !moved.isEmpty {
            // A page emptied by that loop has nothing left to draw — unless it
            // is the first, which still carries the header, the summary and the
            // scope.
            if pages[pages.count - 1].isEmpty && pages.count > 1 { pages.removeLast() }
            pages.append(moved)
        }
        return pages
    }

    /// Room for line items on a page, before anything specific to it.
    private static let pageBudget: CGFloat =
        PageMetrics.height - PageMetrics.margin * 2 - Layout.tableHeader - Layout.footer

    /// Everything above the table on the first page — the logo, the business
    /// name and its contact lines, the parties row, the summary and the scope.
    /// All of it is as tall as the user's own words.
    private static func headerHeight(_ document: QuoteDocument) -> CGFloat {
        var used = Layout.headerBlock
        used += Layout.partiesRow
        // A rule below the recipient block keeps the header information as a
        // distinct, aligned section before the quote body begins.
        used += Layout.sectionRule

        if let summary = document.jobSummary, !summary.isEmpty {
            used += Layout.blockGap + Layout.fieldLabel
                + CGFloat(lineCount(summary, width: PageMetrics.contentWidth, size: 11))
                * Layout.bodyLine
        }
        if !document.scope.isEmpty {
            used += Layout.blockGap + Layout.fieldLabel
            for line in document.scope {
                used += CGFloat(lineCount(line, width: PageMetrics.contentWidth - 16, size: 11))
                    * Layout.bodyLine + Layout.scopeGap
            }
        }
        return used
    }

    /// Totals, terms, notes and the acceptance line — whatever the last page has
    /// to carry under the rows.
    private static func tailHeight(_ document: QuoteDocument) -> CGFloat {
        var used = document.taxRate > 0 ? Layout.totalsWithTax : Layout.totals
        used += Layout.acceptance
        for text in [document.business?.defaultTerms, document.business?.defaultNotes] {
            guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            used += Layout.blockGap + Layout.fieldLabel
                + CGFloat(lineCount(text, width: PageMetrics.contentWidth, size: 9))
                * Layout.smallLine
        }
        return used
    }

    /// A row is one line of description plus its padding, and taller when the
    /// description wraps.
    private static func rowHeight(_ item: QuoteLineItem) -> CGFloat {
        let text = item.description ?? ""
        let lines = lineCount(text, width: Layout.descriptionWidth, size: 10.5)
        return Layout.rowPadding + CGFloat(lines) * Layout.rowLine
    }

    /// Roughly how many lines a string takes at a given width and size.
    ///
    /// Character counting rather than real text measurement: this runs before
    /// any view exists, and being a line out on a page that already reserves
    /// spare room changes nothing. 0.52em is a fair average advance for the
    /// faces this document uses.
    private static func lineCount(_ text: String, width: CGFloat, size: CGFloat) -> Int {
        let perLine = max(1, Int(width / (size * 0.52)))
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(perLine)))) }
    }

    /// Measured off `QuoteDocumentPage`, rounded up.
    private enum Layout {
        /// QUOTE mark, metadata, rule, and the two-column sender/recipient panel.
        static let headerBlock: CGFloat = 48
        // Matches the 124 × 44pt letterhead logo and the sender/recipient
        // panel in QuoteDocumentPage. The extra room is reserved here too, so
        // a larger logo cannot push the table past the bottom of page one.
        static let partiesRow: CGFloat = 176
        static let sectionRule: CGFloat = 20
        static let blockGap: CGFloat = 18
        static let bodyLine: CGFloat = 14
        static let smallLine: CGFloat = 12
        static let fieldLabel: CGFloat = 16
        static let scopeGap: CGFloat = 6
        /// Column headings, their rule, and the gap above the table.
        static let tableHeader: CGFloat = 48
        static let footer: CGFloat = 34
        static let totals: CGFloat = 46
        static let totalsWithTax: CGFloat = 96
        static let acceptance: CGFloat = 60
        static let rowPadding: CGFloat = 15
        static let rowLine: CGFloat = 13
        /// What is left for the description after the three numeric columns.
        static let descriptionWidth: CGFloat = PageMetrics.contentWidth - 62 - 74 - 74 - 24
    }

    /// First page as an image, for the share panel's preview.
    @MainActor
    static func thumbnail(_ document: QuoteDocument, width: CGFloat = 320) -> UIImage? {
        let scale = singlePageScale(document)
        let pages = scale == nil ? paginate(document) : [document.lineItems]
        let page = QuoteDocumentPage(document: document, items: pages.first ?? [],
                                     isFirstPage: true,
                                     isLastPage: pages.count == 1,
                                     pageNumber: 1,
                                     pageCount: 1,
                                     contentScale: scale ?? 1)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: PageMetrics.width, height: PageMetrics.height)
        // Twice the size it will be shown at, for a retina screen. The `max(1,)`
        // this had defeated the calculation it wrapped: `width` is smaller than
        // a page, so the ratio is always below 1, and every thumbnail was
        // rendered at full A4 × 2 — about 8MB of pixels for a 46pt tile.
        renderer.scale = width / PageMetrics.width * 2
        return renderer.uiImage
    }

    enum PDFError: Error {
        case couldNotCreateContext
    }
}
