//
//  BusinessService.swift
//  Verbal
//
//  Reads and writes the user's single `business_profiles` row.
//

import Foundation
import Supabase

enum BusinessService {
    private static var client: SupabaseClient { SupabaseManager.client }

    /// Fetch the user's business profile, or nil if they haven't set one up yet.
    static func fetch() async throws -> BusinessProfile? {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let rows: [BusinessProfile] = try await client
            .from("business_profiles")
            .select()
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Create or update the user's business profile (keyed on user_id).
    static func save(_ profile: BusinessProfile) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        // Email isn't collected in the form — it's the signed-in account email.
        var profile = profile
        profile.email = profile.email ?? client.auth.currentUser?.email
        let payload = Payload(userID: userID, profile: profile)
        try await client
            .from("business_profiles")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }

    /// Insert/update shape — the profile fields plus the owning user_id. Every
    /// editable column belongs here: one left out is silently dropped on save,
    /// which reads as "saved" in the UI and as "never changed" in the database.
    private struct Payload: Encodable {
        let userID: UUID
        let businessName: String?
        let logoUrl: String?
        let phone: String?
        let email: String?
        let address: String?
        let taxNumber: String?
        let currency: String
        let defaultValidityDays: Int
        let defaultTaxRate: Double
        let defaultTerms: String?
        let defaultNotes: String?

        init(userID: UUID, profile: BusinessProfile) {
            self.userID = userID
            self.businessName = profile.businessName
            self.logoUrl = profile.logoUrl
            self.phone = profile.phone
            self.email = profile.email
            self.address = profile.address
            self.taxNumber = profile.taxNumber
            self.currency = profile.currency
            self.defaultValidityDays = profile.defaultValidityDays
            self.defaultTaxRate = profile.defaultTaxRate
            self.defaultTerms = profile.defaultTerms
            self.defaultNotes = profile.defaultNotes
        }

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case businessName = "business_name"
            case logoUrl = "logo_url"
            case phone, email, address
            case taxNumber = "tax_number"
            case currency
            case defaultValidityDays = "default_validity_days"
            case defaultTaxRate = "default_tax_rate"
            case defaultTerms = "default_terms"
            case defaultNotes = "default_notes"
        }
    }
}
