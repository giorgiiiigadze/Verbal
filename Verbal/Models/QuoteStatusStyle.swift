//
//  QuoteStatusStyle.swift
//  Verbal
//
//  The one place that says what colour a status is.
//
//  Read by the pill on a list row and by the status chip on the quote screen.
//  Held here rather than in either of them because a quote that is amber in the
//  list and blue on its own page is two different quotes as far as the eye is
//  concerned, and the second copy of a switch like this is where that starts.
//

import SwiftUI

enum QuoteStatusStyle {
    /// Ink for the label.
    static func text(_ status: String) -> Color {
        switch status {
        // Violet, and specifically not orange: draft is the state every quote
        // starts in, not a warning, and spending the app's one warm colour on
        // it would leave nothing to say when something actually is wrong — the
        // "2 unpriced" badge sits on the same rows.
        //
        // It was grey until it turned out grey was saying two things at once.
        // Expired is grey, and an expired quote is over; a draft is the one
        // status where something is still owed by the user, and reading as
        // dead is exactly wrong for it.
        case "draft": return Color(.statusDraftText)
        case "viewed": return .white
        case "accepted": return Color(.statusAcceptedText)
        case "declined": return Color(.statusDeclinedText)
        case "expired": return Color(.statusMutedText)
        default: return Color(.statusSentText)
        }
    }

    /// The ground it sits on.
    static func fill(_ status: String) -> Color {
        switch status {
        case "draft": return Color(.statusDraftFill)
        // Dark blue, separate from Sent. Viewed is the moment the customer has
        // actually opened the quote, and it needs to be distinguishable at a
        // glance without relying only on the eye glyph.
        case "viewed": return Color(.blueAccentText)
        case "accepted": return Color(.statusAcceptedFill)
        case "declined": return Color(.statusDeclinedFill)
        case "expired": return Color(.statusMutedFill)
        default: return Color(.statusSentFill)
        }
    }
}
