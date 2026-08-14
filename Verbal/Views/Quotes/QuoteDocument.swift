//
//  QuoteDocument.swift
//  Verbal
//
//  The data a rendered quote needs, plus the A4 page metrics it's laid out to.
//  Gathered from the quote, its line items and the user's business profile, then
//  handed to QuoteDocumentPage / QuotePDF to print.
//

import SwiftUI
import UIKit

/// A4 at 72dpi, the unit CoreGraphics uses for PDF pages.
enum PageMetrics {
    static let width: CGFloat = 595
    static let height: CGFloat = 842
    static let margin: CGFloat = 44
    static var contentWidth: CGFloat { width - margin * 2 }
}

/// The data a rendered quote needs, gathered from the quote, its line items
/// and the user's business profile.
struct QuoteDocument {
    let title: String
    let number: String?
    let clientName: String?
    let createdAt: Date
    let validityDate: Date?
    let jobSummary: String?
    let scope: [String]
    let lineItems: [QuoteLineItem]
    let subtotal: Double
    /// Percentage (20 = 20%) and its amount. A zero rate prints no tax line.
    let taxRate: Double
    let taxAmount: Double
    let total: Double
    let currency: String?
    let business: BusinessProfile?
    /// Passed as an image rather than a URL: the page is rendered synchronously
    /// into a PDF, so there is no moment at which it could wait for a download.
    /// It comes from the copy the session already holds, which is also why a
    /// quote shared with no signal still goes out headed.
    var logo: UIImage?

    var businessName: String {
        let name = business?.businessName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) ? name! : "Quote"
    }

    /// Contact lines shown under the business name, blank ones dropped.
    var businessContact: [String] {
        [business?.phone, business?.email, business?.address]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Filename used when the PDF is shared — a real name, not "document.pdf".
    var fileName: String {
        var parts: [String] = []
        if let number, !number.isEmpty { parts.append("Quote \(number)") } else { parts.append("Quote") }
        let subject = clientName?.isEmpty == false ? clientName! : title
        if !subject.isEmpty { parts.append(subject) }
        let joined = parts.joined(separator: " — ")
        let safe = joined.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
        return "\(safe).pdf"
    }
}
