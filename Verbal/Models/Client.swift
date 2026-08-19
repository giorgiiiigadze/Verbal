//
//  Client.swift
//  Verbal
//
//  Who a client is, to this app: a name and the quotes carrying it. Derived
//  from the quote list rather than fetched, which is why it lives beside the
//  quote model rather than in the tab that draws it.
//

import Foundation

/// One person, and every quote with their name on it. Derived rather than
/// fetched, so it holds quotes rather than ids.
struct Client: Identifiable, Hashable {
    let name: String
    let quotes: [QuoteSummary]

    /// Case-folded, matching how the group was built — two spellings of one
    /// name must not become two rows with the same identity.
    var id: String { name.lowercased() }

    /// For a client who no longer has any quotes — see `ClientDetailView`.
    init(name: String, quotes: [QuoteSummary]) {
        self.name = name
        self.quotes = quotes
    }

    init?(_ quotes: [QuoteSummary]) {
        guard let first = quotes.first else { return nil }
        // The most recent spelling wins: it's the one they last typed, and so
        // the one most likely to be right.
        let newest = quotes.max { $0.createdAt < $1.createdAt } ?? first
        name = (newest.clientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.quotes = quotes.sorted { $0.createdAt > $1.createdAt }
    }

    var lastQuoted: Date? { quotes.map(\.createdAt).max() }

    var subtitle: String {
        let count = "\(quotes.count) quote\(quotes.count == 1 ? "" : "s")"
        guard let lastQuoted else { return count }
        return "\(count) · \(quoteDateLabel(lastQuoted))"
    }

    /// Their total, but only when there is one currency to state it in.
    var singleCurrencyTotal: String? {
        let codes = Set(quotes.map { $0.currency ?? AppCurrency.current.rawValue })
        guard let code = codes.first, codes.count == 1 else { return nil }
        return AppCurrency.format(quotes.reduce(0) { $0 + $1.total }, code: code)
    }

    // Equality and hashing are synthesised, over the quotes as well as the
    // name. They used to compare `id` alone, which reads as harmless — two
    // spellings of a name are one person — but it made a client whose quote
    // just changed status equal to the client before the change, so SwiftUI
    // skipped redrawing that row. The tab kept showing Declined while the
    // client's own page, which rebuilds from the session every pass, showed
    // Viewed.
    //
    // Identity stays the case-folded name: that is what `id` is for, and it is
    // a different question from whether anything about them has changed.
}

/// One person, as something that can be pushed.
///
/// The client's own `id` rather than the `Client` itself: a navigation value
/// has to keep the same hash for as long as its screen is up, and `Client`
/// hashes over its quotes — so editing one from that very screen would change
/// the value the stack is holding and pull the page out from under the user.
/// A key can't go stale, and the page reads the person from the session anyway.
struct ClientKey: Hashable {
    /// Their case-folded name, which is what `Client.id` is.
    let id: String
    /// Carried so the page has something to put at the top in the moment after
    /// their last quote is deleted, before it is popped. Payload, not identity:
    /// equality and hashing are on `id` alone, the same reason a quote hashes
    /// on its own id.
    let name: String

    static func == (lhs: ClientKey, rhs: ClientKey) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
