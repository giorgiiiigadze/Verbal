//
//  QuotePDF.swift
//  Verbal
//
//  Renders a quote to a PDF file the user can send to a client.
//

import SwiftUI
import UIKit

enum QuotePDF {
    /// Line items per page. The first page also carries the header, summary and
    /// scope, so it fits fewer; these are deliberately conservative — a short
    /// page looks fine, an overflowing one looks broken.
    private static let itemsOnFirstPage = 9
    private static let itemsOnLaterPages = 20

    /// Render `document` to a PDF in the temporary directory and return its URL.
    /// Runs on the main actor because it rasterizes SwiftUI views.
    @MainActor
    static func write(_ document: QuoteDocument) throws -> URL {
        let pages = paginate(document.lineItems)
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
                pageCount: pages.count
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
        return url
    }

    /// Split line items across pages, keeping the first page shorter to make
    /// room for the header block.
    private static func paginate(_ items: [QuoteLineItem]) -> [[QuoteLineItem]] {
        guard !items.isEmpty else { return [[]] }
        var pages: [[QuoteLineItem]] = []
        var remaining = items[...]

        let firstCount = min(itemsOnFirstPage, remaining.count)
        pages.append(Array(remaining.prefix(firstCount)))
        remaining = remaining.dropFirst(firstCount)

        while !remaining.isEmpty {
            let count = min(itemsOnLaterPages, remaining.count)
            pages.append(Array(remaining.prefix(count)))
            remaining = remaining.dropFirst(count)
        }
        return pages
    }

    /// First page as an image, for the share panel's preview.
    @MainActor
    static func thumbnail(_ document: QuoteDocument, width: CGFloat = 320) -> UIImage? {
        let items = paginate(document.lineItems).first ?? []
        let page = QuoteDocumentPage(document: document, items: items,
                                     isFirstPage: true,
                                     isLastPage: document.lineItems.count <= itemsOnFirstPage,
                                     pageNumber: 1,
                                     pageCount: 1)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: PageMetrics.width, height: PageMetrics.height)
        renderer.scale = max(1, width / PageMetrics.width) * 2
        return renderer.uiImage
    }

    enum PDFError: Error {
        case couldNotCreateContext
    }
}
