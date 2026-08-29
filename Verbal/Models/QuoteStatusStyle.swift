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
        // Gray, not orange. Draft is the state every quote starts in — it isn't
        // a warning, and spending the app's one warm colour on it left nothing
        // to say when something actually is wrong.
        case "draft": return Color(.statusMutedText)
        case "viewed": return Color(.statusViewedText)
        case "accepted": return Color(.statusAcceptedText)
        case "declined": return Color(.statusDeclinedText)
        case "expired": return Color(.statusMutedText)
        default: return Color(.statusSentText)
        }
    }

    /// The ground it sits on.
    static func fill(_ status: String) -> Color {
        switch status {
        case "draft": return Color(.statusMutedFill)
        // Viewed needs a quieter blue ground in dark mode. The app accent is
        // intentionally bright there for buttons and links, but it makes this
        // small status pill look like an active control rather than a state.
        case "viewed": return Color(.statusViewedFill)
        case "accepted": return Color(.statusAcceptedFill)
        case "declined": return Color(.statusDeclinedFill)
        case "expired": return Color(.statusMutedFill)
        default: return Color(.statusSentFill)
        }
    }
}
