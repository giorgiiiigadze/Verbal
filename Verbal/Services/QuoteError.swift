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
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You need to be signed in to save a quote."
        }
    }
}
