//
//  QuoteService+RateCard.swift
//  Verbal
//
//  The saved rates, and the prices spoken into quotes that could become one.
//

import Foundation
import Supabase

extension QuoteService {
    static func fetchRateCard(activeOnly: Bool = false) async throws -> [RateCardItem] {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let query = client
            .from("rate_card_items")
            .select("id, name, unit, unit_price, type, active")
            .eq("user_id", value: userID)
        let filtered = activeOnly ? query.eq("active", value: true) : query
        let response: PostgrestResponse<[RateCardItem]> = try await filtered
            .order("name", ascending: true)
            .execute()
        // Only the full card is cached; the active-only variant is a subset and
        // would overwrite it with less than the Rate Card tab needs to show.
        if !activeOnly {
            LocalCache.save(response.data, for: .rateCard, userID: userID)
        }
        return response.value
    }

    static func addRateCardItem(name: String, unit: String?, unitPrice: Double?, type: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        try await client.from("rate_card_items").insert(
            RateCardInsert(user_id: userID, name: name, unit: unit, unit_price: unitPrice, type: type, active: true)
        ).execute()
    }

    /// Rewrite a saved rate. Until this existed a price could only be corrected
    /// by deleting the rate and retyping it, which is how the card ended up
    /// holding the same job twice at different prices.
    static func updateRateCardItem(id: UUID, name: String, unit: String?,
                                   unitPrice: Double?, type: String) async throws {
        struct Payload: Encodable {
            let name: String
            let unit: String?
            let unitPrice: Double?
            let type: String
            enum CodingKeys: String, CodingKey {
                case name, unit, type
                case unitPrice = "unit_price"
            }
        }
        try await client
            .from("rate_card_items")
            .update(Payload(name: name, unit: unit, unitPrice: unitPrice, type: type))
            .eq("id", value: id)
            .execute()
    }

    /// Update one saved rate's price. Used when the user changes their main
    /// currency and chooses to reprice the rate card rather than relabel it.
    static func updateRateCardPrice(id: UUID, unitPrice: Double) async throws {
        try await client
            .from("rate_card_items")
            .update(["unit_price": unitPrice])
            .eq("id", value: id)
            .execute()
    }

    static func deleteRateCardItem(id: UUID) async throws {
        try await client.from("rate_card_items").delete().eq("id", value: id).execute()
    }

    /// Priced lines from recent quotes that the rate card doesn't hold yet.
    ///
    /// A spoken price that worked once will work again, but only if it's saved —
    /// otherwise the same job gets priced from memory every time. This is the
    /// offer `SaveRatesSheet` makes at the end of a recording, made again later
    /// for the ones that got away.
    ///
    /// `price_source` of `spoken` is the point: a line priced from the rate card
    /// is already saved by definition, and a `missing` one has no price to save.
    static func rateCandidates(notIn existing: [RateCardItem],
                               limit: Int = 80) async throws -> [RateCandidate] {
        try await recentSpokenPrices(limit: limit).filter { candidate in
            !existing.contains { $0.looksLike(candidate.name) }
        }
    }

    /// The same lines, before they're measured against the rate card.
    ///
    /// Split out so the fetch can run alongside the rate card during bootstrap
    /// instead of queueing behind it — the comparison is cheap and local, and
    /// waiting for one list to arrive before asking for the other is what would
    /// make the offer show up late.
    static func recentSpokenPrices(limit: Int = 80) async throws -> [RateCandidate] {
        struct Row: Decodable {
            let description: String?
            let unit: String?
            let unitPrice: Double?
            let type: String

            enum CodingKeys: String, CodingKey {
                case description, unit, type
                case unitPrice = "unit_price"
            }
        }

        let response: PostgrestResponse<[Row]> = try await client
            .from("quote_line_items")
            .select("description, unit, unit_price, type")
            .eq("price_source", value: "spoken")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        var seen = Set<String>()
        var candidates: [RateCandidate] = []
        for row in response.value {
            guard let name = row.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                  name.count >= 3,
                  let price = row.unitPrice, price > 0
            else { continue }
            // The same job quoted three times is one thing to offer, and the
            // newest wording of it is the one the user last chose.
            guard seen.insert(name.lowercased()).inserted else { continue }
            candidates.append(RateCandidate(name: name, unit: row.unit,
                                            unitPrice: price, type: row.type))
        }
        return candidates
    }
}

private struct RateCardInsert: Encodable {
    let user_id: UUID
    let name: String
    let unit: String?
    let unit_price: Double?
    let type: String
    let active: Bool
}
