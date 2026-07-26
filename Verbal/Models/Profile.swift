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

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case bio
    }
}
