//
//  Profile.swift
//  Verbal
//

import Foundation

struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var username: String?
    var fullName: String?
    var avatarUrl: String?
    var bio: String?
    /// Read-only here, and deliberately so: the client is granted update on
    /// every other column of this row and not on this one, because a paywall
    /// that the app it gates can write to is not a paywall. Written by the
    /// server; StoreKit's `currentEntitlements` is what the app actually acts
    /// on, so this is for display and for the server's own use.
    var subscriptionStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case bio
        case subscriptionStatus = "subscription_status"
    }
}
