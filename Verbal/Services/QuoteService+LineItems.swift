//
//  QuoteService+LineItems.swift
//  Verbal
//
//  The priced lines of a quote, and the subtotal they add up to.
//

import Foundation
import Supabase

extension QuoteService {
    /// Fetch a quote's line items, in order.
    static func fetchLineItems(quoteId: UUID) async throws -> [QuoteLineItem] {
        let response: PostgrestResponse<[QuoteLineItem]> = try await client
            .from("quote_line_items")
            .select("id, description, type, quantity, unit, unit_price, price_source, confidence, position")
            .eq("quote_id", value: quoteId)
            .order("position", ascending: true)
            .execute()
        // Cached so a quote opened offline shows its work rather than an empty
        // table — the list surviving without its contents is half a feature.
        if let userID = client.auth.currentUser?.id {
            LocalCache.save(response.data, for: .lineItems(quoteID: quoteId), userID: userID)
        }
        return response.value
    }

    /// Insert a new line item into a quote.
    static func insertLineItem(quoteId: UUID, description: String?, type: String, quantity: Double?,
                               unit: String?, unitPrice: Double?, priceSource: String,
                               position: Int) async throws {
        struct Insert: Encodable {
            let quoteId: UUID
            let fields: LineItemFields
            // Flatten quote_id alongside the shared editable fields.
            enum CodingKeys: String, CodingKey { case quoteId = "quote_id" }
            func encode(to encoder: Encoder) throws {
                try fields.encode(to: encoder)
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(quoteId, forKey: .quoteId)
            }
        }
        try await client
            .from("quote_line_items")
            .insert(Insert(quoteId: quoteId,
                           fields: LineItemFields(description: description, type: type,
                                                  quantity: quantity, unit: unit,
                                                  unitPrice: unitPrice, priceSource: priceSource,
                                                  position: position)))
            .execute()
    }

    /// Overwrite a line item's editable fields (quote_id is left untouched).
    static func updateLineItem(id: UUID, description: String?, type: String, quantity: Double?,
                               unit: String?, unitPrice: Double?, priceSource: String,
                               position: Int) async throws {
        try await client
            .from("quote_line_items")
            .update(LineItemFields(description: description, type: type, quantity: quantity,
                                   unit: unit, unitPrice: unitPrice, priceSource: priceSource,
                                   position: position))
            .eq("id", value: id)
            .execute()
    }

    /// Delete a single line item.
    static func deleteLineItem(id: UUID) async throws {
        try await client.from("quote_line_items").delete().eq("id", value: id).execute()
    }

    /// Fill in a price on a draft that was already banked, addressed by the
    /// line's position. Line items are inserted in order, so position finds
    /// them without the review screen having to carry server ids around.
    /// Quantity goes along because an unpriced line often has none, and a unit
    /// price with no quantity still totals nothing.
    static func setLineItemPrice(quoteId: UUID, position: Int,
                                 quantity: Double, unitPrice: Double) async throws {
        struct Payload: Encodable {
            let quantity: Double
            let unitPrice: Double
            let priceSource: String
            enum CodingKeys: String, CodingKey {
                case quantity
                case unitPrice = "unit_price"
                case priceSource = "price_source"
            }
        }
        try await client
            .from("quote_line_items")
            .update(Payload(quantity: quantity, unitPrice: unitPrice, priceSource: "rate_card"))
            .eq("quote_id", value: quoteId)
            .eq("position", value: position)
            .execute()
    }

    /// Update a single line item's unit price (used when converting a quote).
    static func updateLineItemPrice(id: UUID, unitPrice: Double) async throws {
        try await client
            .from("quote_line_items")
            .update(["unit_price": unitPrice])
            .eq("id", value: id)
            .execute()
    }

    /// Recompute a quote's subtotal after its line items changed. `tax_amount`
    /// and `total` are derived from it by a database trigger.
    static func updateSubtotal(id: UUID, subtotal: Double) async throws {
        struct Payload: Encodable { let subtotal: Double }
        try await client
            .from("quotes")
            .update(Payload(subtotal: subtotal))
            .eq("id", value: id)
            .execute()
    }
}

/// The editable columns of a line item (no quote_id), shared by update & insert.
private struct LineItemFields: Encodable {
    let description: String?
    let type: String
    let quantity: Double?
    let unit: String?
    let unitPrice: Double?
    let priceSource: String?
    let position: Int

    enum CodingKeys: String, CodingKey {
        case description, type, quantity, unit
        case unitPrice = "unit_price"
        case priceSource = "price_source"
        case position, confidence
    }

    /// Written by hand so every column is sent, nil included.
    ///
    /// A synthesised encoder leaves a nil optional out of the JSON entirely,
    /// and an absent column in a PATCH tells PostgREST to leave that column
    /// as it is. So clearing a price sent `price_source: "missing"` and kept
    /// the old `unit_price` beside it — the row disagreed with itself, and the
    /// price the user had just deleted was still there the next time they
    /// opened the editor.
    ///
    /// `confidence` is always null. It is the model's read on a line it heard
    /// spoken, and once the user has typed over that line there is nothing
    /// left for the read to be about — a price someone has just corrected by
    /// hand should not still be telling them it is worth checking. The same
    /// applies to a line inserted here, which the model never saw at all.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unit, forKey: .unit)
        try container.encode(unitPrice, forKey: .unitPrice)
        try container.encode(priceSource, forKey: .priceSource)
        try container.encode(position, forKey: .position)
        try container.encodeNil(forKey: .confidence)
    }
}
