//
//  BusinessProfile.swift
//  Verbal
//
//  The tradesperson's business identity and quote defaults. One row per user
//  in `business_profiles`, edited from Settings → Business. Appears on the
//  quotes sent to customers.
//

import Foundation

struct BusinessProfile: Codable, Sendable {
    var businessName: String?
    var logoUrl: String?
    var phone: String?
    var email: String?
    var address: String?
    var taxNumber: String?
    var currency: String
    var defaultValidityDays: Int
    /// Tax percentage applied to new quotes, e.g. 20 for 20% VAT. Zero means
    /// the user isn't tax registered and no tax line is shown.
    var defaultTaxRate: Double
    var defaultTerms: String?
    var defaultNotes: String?

    enum CodingKeys: String, CodingKey {
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

    /// A blank profile using the app's current currency and the DB default validity.
    static var empty: BusinessProfile {
        BusinessProfile(businessName: nil, logoUrl: nil, phone: nil, email: nil,
                        address: nil, taxNumber: nil,
                        currency: AppCurrency.current.rawValue,
                        defaultValidityDays: 14, defaultTaxRate: 0,
                        defaultTerms: nil, defaultNotes: nil)
    }
}
