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
    /// What they do — "Electrician", "Plumber". Asked once at onboarding and
    /// sent with every extraction as trade context.
    var trade: String?
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
    /// Printed in front of the allocated number — "INV-", "2026-". Never part of
    /// the number itself: that column is a bare digit sequence the database
    /// allocates and enforces uniqueness on.
    var quoteNumberPrefix: String?
    /// Where this account's numbering begins, for a trade that had a book of
    /// quotes before it had this app.
    var quoteNumberStart: Int

    enum CodingKeys: String, CodingKey {
        case businessName = "business_name"
        case logoUrl = "logo_url"
        case trade
        case phone, email, address
        case taxNumber = "tax_number"
        case currency
        case defaultValidityDays = "default_validity_days"
        case defaultTaxRate = "default_tax_rate"
        case defaultTerms = "default_terms"
        case defaultNotes = "default_notes"
        case quoteNumberPrefix = "quote_number_prefix"
        case quoteNumberStart = "quote_number_start"
    }

    /// Decoded field by field, defaulting anything the row doesn't carry.
    ///
    /// The synthesized version required every non-optional column to be present,
    /// so the moment a column was added to the model ahead of the migration that
    /// creates it, the whole profile failed to decode — and a screen of business
    /// details came up blank rather than one field being empty. A profile row is
    /// worth reading in whatever state it arrives; the fields are all defaults
    /// the app can supply.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        businessName = try c.decodeIfPresent(String.self, forKey: .businessName)
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl)
        trade = try c.decodeIfPresent(String.self, forKey: .trade)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        taxNumber = try c.decodeIfPresent(String.self, forKey: .taxNumber)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
            ?? AppCurrency.current.rawValue
        defaultValidityDays = try c.decodeIfPresent(Int.self, forKey: .defaultValidityDays) ?? 14
        defaultTaxRate = try c.decodeIfPresent(Double.self, forKey: .defaultTaxRate) ?? 0
        defaultTerms = try c.decodeIfPresent(String.self, forKey: .defaultTerms)
        defaultNotes = try c.decodeIfPresent(String.self, forKey: .defaultNotes)
        quoteNumberPrefix = try c.decodeIfPresent(String.self, forKey: .quoteNumberPrefix)
        quoteNumberStart = try c.decodeIfPresent(Int.self, forKey: .quoteNumberStart) ?? 1
    }

    /// Kept because the decoder above suppresses the synthesized one, and
    /// `empty` and the save path both build a profile by hand.
    init(businessName: String?, logoUrl: String?, trade: String?, phone: String?,
         email: String?, address: String?, taxNumber: String?, currency: String,
         defaultValidityDays: Int, defaultTaxRate: Double, defaultTerms: String?,
         defaultNotes: String?, quoteNumberPrefix: String?, quoteNumberStart: Int) {
        self.businessName = businessName
        self.logoUrl = logoUrl
        self.trade = trade
        self.phone = phone
        self.email = email
        self.address = address
        self.taxNumber = taxNumber
        self.currency = currency
        self.defaultValidityDays = defaultValidityDays
        self.defaultTaxRate = defaultTaxRate
        self.defaultTerms = defaultTerms
        self.defaultNotes = defaultNotes
        self.quoteNumberPrefix = quoteNumberPrefix
        self.quoteNumberStart = quoteNumberStart
    }

    /// A blank profile using the app's current currency and the DB default validity.
    static var empty: BusinessProfile {
        BusinessProfile(businessName: nil, logoUrl: nil, trade: nil, phone: nil, email: nil,
                        address: nil, taxNumber: nil,
                        currency: AppCurrency.current.rawValue,
                        defaultValidityDays: 14, defaultTaxRate: 0,
                        defaultTerms: nil, defaultNotes: nil,
                        quoteNumberPrefix: nil, quoteNumberStart: 1)
    }
}
