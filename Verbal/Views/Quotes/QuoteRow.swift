//
//  QuoteRow.swift
//  Verbal
//
//  The quote card used in the Home list and on a client's detail screen, plus
//  the loading placeholder built to its exact geometry.
//

import SwiftUI

/// Internal rather than private: the clients tab lists a client's quotes and
/// they have to be the same row, or the app has two ways of drawing a quote and
/// they drift.
struct QuoteRow: View {
    let quote: QuoteSummary
    /// Lines this quote can't price yet. Passed in because the summary row
    /// doesn't know what's inside a quote — the list reads it from the prefetch.
    var unpricedCount: Int = 0
    /// True when the row already sits under the client it belongs to.
    ///
    /// The clients thread hangs every one of a person's quotes off a header
    /// carrying their name, so repeating it on each row said the same thing
    /// five times down one column. The timestamp stays — it is the only thing
    /// telling the quotes in a thread apart.
    var clientIsKnown: Bool = false
    /// Matches the document cards on the quote screen. The old 22pt radius
    /// made a dense list of quotes look softer and more dashboard-like than
    /// the details page it opens.
    var cornerRadius: CGFloat = 16
    var topCornerRadius: CGFloat? = nil
    var bottomCornerRadius: CGFloat? = nil
    var showsBorder: Bool = true

    private var rowShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: topCornerRadius ?? cornerRadius,
                bottomLeading: bottomCornerRadius ?? cornerRadius,
                bottomTrailing: bottomCornerRadius ?? cornerRadius,
                topTrailing: topCornerRadius ?? cornerRadius
            ),
            style: .continuous
        )
    }

    /// Drafts only, and it takes the status pill's place rather than adding to
    /// the row.
    ///
    /// "Draft" is the least informative thing the pill could say — it is the
    /// state every quote starts in — so the slot is spent on the exception
    /// instead. Once a quote has gone out the trade is off: the gap
    /// was sent deliberately as TBC, and what the customer has done with it
    /// since is the thing worth reading.
    private var showsUnpriced: Bool {
        unpricedCount > 0 && quote.effectiveStatus == "draft"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if quote.pinned {
                        // Secondary, not the brand blue it was. The card is
                        // no longer tinted, so the glyph is the whole signal —
                        // and a signal that has the section heading above it
                        // and the pin's own shape does not need a colour too.
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            // Springs in from nothing at the corner it will
                            // occupy, so the pin reads as being pressed into
                            // the card rather than fading onto it.
                            .transition(
                                .scale(scale: 0.1, anchor: .bottomLeading)
                                    .combined(with: .opacity)
                            )
                    }
                    Text(quote.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                }
                // Lead with the client when there is one — job titles repeat
                // ("Bathroom re-tiling" three times over), names don't.
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(AppCurrency.format(quote.total, code: quote.currency))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
                statusPill
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        // Enough air for a calm document stack without the cards becoming
        // taller than the information they carry.
        .padding(.vertical, 16)
        // One fill for every row, pinned or not. A pinned quote already sits
        // under its own heading at the top of the list, which says where it is
        // better than a colour can — and royalBlue25 is the tint the app uses
        // for things asking to be tapped (the outstanding band, the ready-to-add
        // card), so a pin read as more urgent than the money above it.
        .background(Color(.cardSurface), in: rowShape)
        .overlay {
            if showsBorder {
                rowShape.strokeBorder(Color(.separator), lineWidth: 0.5)
            }
        }
        .contentShape(.contextMenuPreview, rowShape)
    }

    /// Client name and how long ago the quote went out. The client leads where
    /// it appears: several quotes share the same job title, and names don't.
    private var subtitle: String {
        // Relative, not absolute. "12 Aug" is a fact the reader has to convert
        // before it means anything; "Sent 1w ago" is the conversion already
        // done, and the answer — chase it or leave it — falls out of it. The
        // day headings above the rows still carry the absolute date, and the
        // quote's own screen has it to the minute.
        let age = quoteRelativeLabel(quote.createdAt)
        // Status has its own pill; repeating "Sent" here made each sent quote
        // say the same thing twice before getting to the useful timestamp.
        let when = age
        guard !clientIsKnown,
              let client = quote.clientName, !client.isEmpty else { return when }
        return "\(client) · \(when)"
    }

    /// Small tinted capsule naming the quote's status: gray while nothing has
    /// happened to it, blue once it is out, green or red once it is settled.
    ///
    /// The colours are the `Status*` pairs in the asset catalogue rather than
    /// the system's `.green` / `.red` at some alpha. Those are tuned for iOS
    /// controls — vivid and cool — and a derived 14% tint of one is not a
    /// chosen colour; on a warm off-white page the pills read louder than the
    /// title above them. Each pair here is a muted ink over a ground picked to
    /// go with it, in both appearances.
    ///
    /// "Viewed" is the exception, and deliberately: it's the one state that
    /// reports something the customer did rather than something the user did,
    /// and it's the moment worth acting on. Set like "Sent" — both were
    /// `blueAccentText` on near-identical pale blue — it said the quote had
    /// gone out, when what it actually says is that somebody is reading it.
    private var statusPill: some View {
        HStack(spacing: 4) {
            if quote.effectiveStatus == "viewed" {
                Image(systemName: "eye.fill")
                    .font(.caption2)
            }
            Text(showsUnpriced ? "\(unpricedCount) unpriced" : pillLabel)
                // Same reasoning as the chip on the quote screen: the fill
                // already fades when the status changes, so a label that cuts
                // is the one part out of step.
                .contentTransition(.opacity)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(pillForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(pillBackground, in: Capsule())
    }

    private var pillLabel: String {
        switch quote.effectiveStatus {
        case "draft": return "Draft"
        case "sent": return "Sent"
        case "viewed": return "Viewed"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        case "expired": return "Expired"
        default: return quote.effectiveStatus.capitalized
        }
    }

    private var pillForeground: Color {
        if showsUnpriced { return Color(.statusWarningText) }
        return QuoteStatusStyle.text(quote.effectiveStatus)
    }

    private var pillBackground: Color {
        if showsUnpriced { return Color(.statusWarningFill) }
        return QuoteStatusStyle.fill(quote.effectiveStatus)
    }
}

/// A quote card with its content replaced by bars. Deliberately built to
/// `QuoteRow`'s geometry — same radius, padding, border and column positions —
/// so the real cards land where the placeholders were instead of shifting the
/// page as they arrive.
struct QuoteRowSkeleton: View {
    let titleWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                bar(titleWidth, 15)
                bar(titleWidth * 0.55, 11)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                bar(62, 13)
                bar(52, 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private func bar(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
    }
}
