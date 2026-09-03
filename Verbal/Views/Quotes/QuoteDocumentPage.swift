//
//  QuoteDocumentPage.swift
//  Verbal
//
//  One printed page of a quote. Laid out at A4 point size and rendered to PDF
//  by QuotePDF — never shown on screen directly, except as a preview thumbnail.
//

import SwiftUI
import UIKit

/// One page of the document. `items` is this page's slice of the line items.
struct QuoteDocumentPage: View {
    let document: QuoteDocument
    let items: [QuoteLineItem]
    /// Header, summary and scope print once, on the first page only.
    let isFirstPage: Bool
    /// Totals and terms print once, on the last page only.
    let isLastPage: Bool
    let pageNumber: Int
    let pageCount: Int
    /// Shrinks everything above the footer, to hold a quote that overruns one
    /// page by a little rather than spilling onto a second.
    ///
    /// Set by `QuotePDF`, and only within a few percent of 1 — past that the
    /// document splits instead. The text reflows at the wider measure and is
    /// scaled back down, so this reads as slightly smaller type on the same
    /// margins rather than as a shrunken page floating in white.
    var contentScale: CGFloat = 1

    private var currency: String? { document.currency }

    /// The document's one accent — the brand navy, fixed rather than themed
    /// because this is print, not app chrome.
    private static let ink = Color(red: 0.098, green: 0.157, blue: 0.408)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The footer keeps its size and its place at the foot of the page;
            // only the document above it shrinks.
            content
                .frame(width: PageMetrics.contentWidth / contentScale, alignment: .topLeading)
                .scaleEffect(contentScale, anchor: .topLeading)
                .frame(width: PageMetrics.contentWidth, alignment: .topLeading)

            Spacer(minLength: 0)

            pageFooter
        }
        .padding(PageMetrics.margin)
        .frame(width: PageMetrics.width, height: PageMetrics.height, alignment: .topLeading)
        .background(.white)
        // The document is a printed artifact: always light, never the app's theme.
        .environment(\.colorScheme, .light)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirstPage {
                header
                sectionRule.padding(.top, 16)
                partiesRow.padding(.top, 18)
                sectionRule.padding(.top, 18)
                if let summary = document.jobSummary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Job summary")
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.black.opacity(0.75))
                    }
                    .padding(.top, 18)
                }
                if !document.scope.isEmpty {
                    scopeSection.padding(.top, 18)
                }
            }

            if !items.isEmpty {
                lineItemTable.padding(.top, isFirstPage ? 22 : 0)
            }

            if isLastPage {
                totals.padding(.top, 18)
                if let terms = document.business?.defaultTerms,
                   !terms.trimmingCharacters(in: .whitespaces).isEmpty {
                    footerBlock(title: "Terms", body: terms).padding(.top, 22)
                }
                if let notes = document.business?.defaultNotes,
                   !notes.trimmingCharacters(in: .whitespaces).isEmpty {
                    footerBlock(title: "Notes", body: notes).padding(.top, 14)
                }
                acceptance.padding(.top, 22)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            quoteNumber
            Spacer(minLength: 20)
            headerMetadata
        }
    }

    private var quoteNumber: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("Quote no.")
            Text(document.number?.isEmpty == false ? document.number! : "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.8))
        }
    }

    /// The identifying information belongs together at the top of the page,
    /// where a client can find it without scanning the body of the quote.
    private var headerMetadata: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("Issued")
                Text(QuoteDateFormat.display(document.createdAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }

            if let validity = document.validityDate {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Valid until")
                    Text(QuoteDateFormat.display(validity))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black.opacity(0.8))
                }
            }
        }
    }

    private var partiesRow: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("From")
                if let logo = document.logo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        // Give the letterhead enough presence to read as a
                        // proper business mark, while preserving every logo's
                        // aspect ratio rather than cropping a wide wordmark.
                        .frame(maxWidth: 124, maxHeight: 44, alignment: .leading)
                }
                Text(document.businessName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.black)
                ForEach(document.businessContact, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.black.opacity(0.65))
                }
                if let tax = document.business?.taxNumber,
                   !tax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Tax no. \(tax)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.black.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(.black.opacity(0.20))
                .frame(width: 1)
                .padding(.vertical, -18)

            VStack(alignment: .leading, spacing: 7) {
                fieldLabel("To")
                Text(document.clientName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? document.clientName! : "Client")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.black)
                    .padding(.top, 4)
                ForEach(document.clientContact, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.black.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 24)
        }
        .frame(minHeight: 86, alignment: .top)
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Scope of work")
            ForEach(document.scope, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(.system(size: 11)).foregroundStyle(.black.opacity(0.5))
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(.black.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lineItemTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").frame(width: 62, alignment: .trailing)
                Text("Unit price").frame(width: 74, alignment: .trailing)
                Text("Amount").frame(width: 74, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.black.opacity(0.55))
            .padding(.bottom, 7)

            tableRule

            // Put each divider immediately before the next row. This keeps it
            // attached to the row boundary even when a page slice starts or a
            // long description changes a row's height.
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    tableRule
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(item.description ?? "—")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.quantityText ?? "—")
                        .frame(width: 62, alignment: .trailing)
                    Text(item.unitPrice.map { AppCurrency.format($0, code: currency) } ?? "—")
                        .frame(width: 74, alignment: .trailing)
                    // "TBC" rather than the app's internal "Needs price" — the
                    // client reads this, and it should look deliberate.
                    Text(item.lineTotal.map { AppCurrency.format($0, code: currency) } ?? "TBC")
                        .frame(width: 74, alignment: .trailing)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.vertical, 7)
            }
        }
    }

    private var tableRule: some View {
        Rectangle()
            .fill(.black.opacity(0.18))
            .frame(height: 1)
    }

    /// Deliberate document rules make the sections read as a controlled grid
    /// rather than a set of floating text blocks.
    private var sectionRule: some View {
        Rectangle()
            .fill(.black.opacity(0.20))
            .frame(height: 1)
    }

    private var totals: some View {
        let unpriced = document.lineItems.filter(\.isMissingPrice).count
        let showsTax = document.taxRate > 0
        return HStack(alignment: .firstTextBaseline) {
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                // Only tax-registered users get a breakdown; for everyone else
                // a lone "Total" is cleaner than a subtotal that repeats it.
                if showsTax {
                    totalsRow(label: "Subtotal", value: document.subtotal)
                    totalsRow(label: "Tax (\(Self.rateText(document.taxRate)))",
                              value: document.taxAmount)
                    Rectangle()
                        .fill(.black.opacity(0.12))
                        .frame(width: 190, height: 0.5)
                        .padding(.vertical, 3)
                }
                HStack(spacing: 26) {
                    Text("Total")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                    Text(AppCurrency.format(document.total, code: currency))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Self.ink)
                }
                if unpriced > 0 {
                    Text("Excludes \(unpriced) item\(unpriced == 1 ? "" : "s") still to be confirmed")
                        .font(.system(size: 9))
                        .foregroundStyle(.black.opacity(0.5))
                }
            }
        }
    }

    private func totalsRow(label: String, value: Double) -> some View {
        HStack(spacing: 26) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.black.opacity(0.6))
            Text(AppCurrency.format(value, code: currency))
                .font(.system(size: 10.5))
                .foregroundStyle(.black.opacity(0.8))
        }
    }

    /// "20%" rather than "20.0%", but keeps a genuine fraction like 8.5%.
    private static func rateText(_ rate: Double) -> String {
        rate == rate.rounded()
            ? "\(Int(rate))%"
            : String(format: "%.2f%%", rate)
    }

    /// Tells the client what to do next — a quote without a call to action
    /// leaves them to work it out themselves.
    private var acceptance: some View {
        let phone = document.business?.phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let how = if let phone, !phone.isEmpty {
            "reply to this message or call \(phone)"
        } else {
            "reply to this message"
        }
        return HStack(spacing: 0) {
            Text("To accept this quote, \(how).")
                .font(.system(size: 10))
                .foregroundStyle(.black.opacity(0.8))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Self.ink.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Anchored to the bottom of every page, so the sheet reads as finished
    /// rather than simply stopping.
    private var pageFooter: some View {
        VStack(spacing: 6) {
            Rectangle().fill(.black.opacity(0.08)).frame(height: 0.5)
            HStack {
                Text(document.businessName)
                    .font(.system(size: 8))
                    .foregroundStyle(.black.opacity(0.45))
                Spacer(minLength: 8)
                if pageCount > 1 {
                    Text("Page \(pageNumber) of \(pageCount)")
                        .font(.system(size: 8))
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
        }
    }

    private func footerBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title)
            Text(body)
                .font(.system(size: 9.5))
                .foregroundStyle(.black.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.black.opacity(0.45))
    }
}
