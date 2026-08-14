//
//  QuoteLineItem.swift
//  Verbal
//
//  A single priced line as stored in `quote_line_items` and shown on the
//  quote detail table.
//

import Foundation

/// A line item shown on the quote detail table.
struct QuoteLineItem: Identifiable, Decodable, Sendable {
    let id: UUID
    let description: String?
    let type: String
    let quantity: Double?
    let unit: String?
    let unitPrice: Double?
    let priceSource: String?
    /// How sure the model was of this line's quantity and price ("high"/"low").
    /// Nil on lines the user typed themselves, and on anything saved before the
    /// field started being persisted.
    let confidence: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id, description, type, quantity, unit
        case unitPrice = "unit_price"
        case priceSource = "price_source"
        case confidence, position
    }

    var isMissingPrice: Bool { priceSource == "missing" || unitPrice == nil }

    var lineTotal: Double? {
        guard let quantity, let unitPrice else { return nil }
        return quantity * unitPrice
    }

    var quantityText: String? { quantityLabel(quantity, unit) }
}
