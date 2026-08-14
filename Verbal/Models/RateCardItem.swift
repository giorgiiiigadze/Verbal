//
//  RateCardItem.swift
//  Verbal
//
//  The user's saved rates and the spoken-price candidates offered back as new
//  rates — the data behind auto-pricing and the Rate Card tab.
//

import Foundation

/// A saved rate-card entry (labor/material/other) used to auto-price quotes.
struct RateCardItem: Identifiable, Decodable, Sendable {
    let id: UUID
    let name: String
    let unit: String?
    let unitPrice: Double?
    let type: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, unit
        case unitPrice = "unit_price"
        case type, active
    }

    var priceText: String? {
        guard let unitPrice else { return nil }
        let amount = AppCurrency.format(unitPrice)
        return [amount, unit].compactMap { $0 }.joined(separator: " / ")
    }

    /// Whether this rate is plausibly the same job as `name`.
    ///
    /// Compared as normalised words rather than raw text. The extraction words
    /// the same job differently on different runs, so matching exactly lets
    /// "Re-tiling" past "Re tiling" — which is how one card came to hold three
    /// prices for tiling and leave the model to choose between them.
    ///
    /// Deliberately loose, and used only to raise the question: a duplicate
    /// that slips through becomes a wrong price in a customer's hands, while a
    /// false match is something the user can see and decline.
    func looksLike(_ name: String) -> Bool {
        let mine = Self.nameWords(self.name)
        let theirs = Self.nameWords(name)
        guard !mine.isEmpty, !theirs.isEmpty else { return false }
        let a = mine.joined(), b = theirs.joined()
        if a == b || a.contains(b) || b.contains(a) { return true }
        // A shared significant word: "Replace toilet" against "Toilet Installation".
        return mine.contains { $0.count >= 5 && theirs.contains($0) }
    }

    /// Lowercased alphanumeric words, so spacing and punctuation stop mattering.
    private static func nameWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

/// A price the user has already spoken into a quote, offered back as a rate.
struct RateCandidate: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let unit: String?
    let unitPrice: Double
    let type: String

    var priceText: String {
        let amount = AppCurrency.format(unitPrice)
        return [amount, unit].compactMap { $0 }.joined(separator: " / ")
    }
}
