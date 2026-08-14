//
//  GeneratedQuote.swift
//  Verbal
//
//  A structured quote produced by the AI extraction, before it's persisted —
//  used in the recording review UI.
//

import Foundation

/// A structured quote produced by the AI, before it's persisted — used in the review UI.
struct GeneratedQuote: Sendable {
    var title: String
    var jobSummary: String
    var scope: [String]
    var notes: String?
    var lineItems: [GeneratedLineItem]
    /// The client the speaker named, if they named one. A suggestion only —
    /// the user's own typing always wins.
    var clientName: String?
    /// What the model wants looked at before this goes to a customer: prices it
    /// couldn't find, quantities it wasn't sure it heard right.
    var flags: [String]
}

struct GeneratedLineItem: Identifiable, Sendable {
    let id = UUID()
    var description: String
    var type: String
    var quantity: Double?
    var unit: String?
    var unitPrice: Double?
    var priceSource: String?
    /// How sure the model was of this line's quantity and price ("high"/"low").
    var confidence: String?

    var isMissingPrice: Bool { priceSource == "missing" || unitPrice == nil }
    var lineTotal: Double? {
        guard let quantity, let unitPrice else { return nil }
        return quantity * unitPrice
    }
    var quantityText: String? { quantityLabel(quantity, unit) }
}
