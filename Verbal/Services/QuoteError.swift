//
//  QuoteError.swift
//  Verbal
//
//  What the services throw. Named for the quote service it started in, but
//  business details and logo uploads report failure with it too.
//

import Foundation

enum QuoteError: LocalizedError {
    case notSignedIn
    /// Extraction ran past its deadline. Worded as something to try again
    /// rather than something that broke, because it usually is — and it says
    /// the recording is safe because that is the user's first fear and the
    /// transcript is, in fact, still on screen behind the message.
    ///
    /// Kept short: this is read in a two-line toast.
    case extractionTimedOut
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in to save a quote."
        case .extractionTimedOut:
            return "That took too long. Your recording is safe — try again."
        }
    }
}
