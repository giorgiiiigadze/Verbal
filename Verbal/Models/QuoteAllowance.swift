//
//  QuoteAllowance.swift
//  Verbal
//
//  How many quotes are left today, as the server counts them.
//
//  The app used to work this out itself: take the device's local midnight,
//  count `quote_usage` rows since then, compare against a constant compiled
//  into the app. Every one of those three steps is now also performed by the
//  database, which is the one that actually refuses — so the app asks rather
//  than computes. Two implementations of "which quotes count as today's" drift,
//  and the shape the drift takes is an app offering an allowance the server
//  then declines.
//

import Foundation

struct QuoteAllowance: Decodable, Sendable, Equatable {
    /// Whether the server can see a verified subscription. Not what the paywall
    /// reads — `Store.isPro` comes from StoreKit and is both faster and the
    /// authority on screen — but worth having when the two disagree, because
    /// that disagreement is what a subscriber being refused looks like.
    let isPro: Bool
    /// The free tier, from the server rather than from a constant here.
    let limit: Int
    let used: Int
    /// Nil for a subscriber: not "none left", but "not counted".
    let remaining: Int?
    /// When the allowance next resets, in the user's own zone. Kept as the
    /// string the server sent rather than a `Date`: nothing reads it yet, and a
    /// date format this decoder happened not to like would fail the whole
    /// response — costing the app the count it actually needs over a field it
    /// doesn't.
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case isPro = "is_pro"
        case limit, used, remaining
        case resetsAt = "resets_at"
    }
}
