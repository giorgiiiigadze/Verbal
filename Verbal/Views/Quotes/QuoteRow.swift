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

    /// Drafts only, and it takes the status pill's place rather than adding to
    /// the row.
    ///
    /// The list is already grouped under "Drafts · 5", so a pill repeating that
    /// word is the least informative thing in the row and can be spent on the
    /// exception instead. Once a quote has gone out the trade is off: the gap
    /// was sent deliberately as TBC, and what the customer has done with it
    /// since is the thing worth reading.
    private var showsUnpriced: Bool {
        unpricedCount > 0 && quote.effectiveStatus == "draft"
    }
    @Environment(\.colorScheme) private var scheme

    /// RoyalBlue600 has no dark variant — it is #192868 in both appearances —
    /// so on a pinned card, which is itself a dark blue in dark mode, the pin
    /// was navy on navy. White in the dark, the same inversion the sign-in
    /// waves needed for the same reason.
    private var pinColor: Color {
        scheme == .dark ? .white : Color(.royalBlue600)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if quote.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(pinColor)
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
        .padding(.vertical, 18)
        .background(quote.pinned ? Color(.royalBlue25) : Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Client name when known, otherwise when the quote was made. The client is
    /// the more useful identifier — several quotes share the same job title.
    private var subtitle: String {
        let age = quote.createdAt.formatted(.relative(presentation: .named))
        guard let client = quote.clientName, !client.isEmpty else { return age }
        return "\(client) · \(age)"
    }

    /// Small tinted capsule naming the quote's status — pale blue for the
    /// working states, green/red for the settled ones.
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
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(pillForeground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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
        if showsUnpriced { return LineItemRow.amber }
        switch quote.effectiveStatus {
        case "draft": return .orange
        case "viewed": return .white
        case "accepted": return .green
        case "declined": return .red
        case "expired": return .secondary
        default: return Color(.blueAccentText)
        }
    }

    private var pillBackground: Color {
        if showsUnpriced { return LineItemRow.amber.opacity(0.14) }
        switch quote.effectiveStatus {
        case "draft": return .orange.opacity(0.14)
        // Filled, where every other state is a tint. The only pill on the
        // screen that has to be seen from across the list.
        case "viewed": return Color(.royalBlue600)
        case "accepted": return .green.opacity(0.14)
        case "declined": return .red.opacity(0.12)
        case "expired": return Color(.separator).opacity(0.5)
        default: return Color(.royalBlue25)
        }
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
        .padding(.vertical, 18)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private func bar(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
    }
}
