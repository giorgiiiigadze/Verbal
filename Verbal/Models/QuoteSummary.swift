//
//  QuoteSummary.swift
//  Verbal
//
//  Lightweight quote row for the Home list, decoded from the `quotes` table.
//

import Foundation

/// Lightweight quote row for the Home list.
/// Equatable so a screen holding its own copy can tell a row that changed from
/// one that didn't — Home adopts edits made through `SessionStore.updateQuote`
/// by comparing against what it already has.
///
/// Hashable so a quote can be pushed as a navigation value. Hashed on `id`
/// alone, deliberately: the synthesised conformance would make a quote a
/// different navigation value the moment one of its fields was edited, and the
/// screen showing it would be torn down mid-edit.
struct QuoteSummary: Identifiable, Decodable, Sendable, Equatable, Hashable {
    let id: UUID
    // Everything the quote screen can edit is `var`: it writes each change
    // straight into `SessionStore.quotes` through `updateQuote`, so the tabs
    // drawn from that list are current without a refetch.
    var title: String?
    var jobSummary: String?
    var total: Double
    var status: String
    let createdAt: Date
    /// ISO 4217 code this quote was priced in. Nil on legacy rows; formatting
    /// falls back to the user's current setting in that case.
    var currency: String?
    /// Pinned quotes sort into a dedicated section at the top of the Home list.
    var pinned: Bool
    /// Client-facing "what we'll do" bullet list (may be empty on legacy rows).
    var scope: [String]

    /// Sequential per-user reference, e.g. "0007". Assigned by a database
    /// trigger on insert, so it's always present on new rows.
    let number: String?
    /// Date the quote stops being valid, as stored ("yyyy-MM-dd"). Kept as text
    /// because Postgres `date` columns aren't ISO-8601 timestamps.
    let validityDateText: String?
    /// Name of the customer this quote is for, via the linked customer row.
    var clientName: String?
    /// Sum of the line items, before tax.
    let subtotal: Double
    /// Tax percentage (20 = 20%) and the resulting amount. Both are computed
    /// by the database from `subtotal`, so they always agree with `total`.
    let taxRate: Double
    let taxAmount: Double

    enum CodingKeys: String, CodingKey {
        case id, title
        case jobSummary = "job_summary"
        case total, status
        case createdAt = "created_at"
        case currency, pinned, scope, number, subtotal
        case taxRate = "tax_rate"
        case taxAmount = "tax_amount"
        case validityDate = "validity_date"
        case customers
    }

    /// Shape of the embedded `customers(name)` relation.
    private struct CustomerRef: Decodable { let name: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        jobSummary = try c.decodeIfPresent(String.self, forKey: .jobSummary)
        total = try c.decode(Double.self, forKey: .total)
        status = try c.decode(String.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        scope = try c.decodeIfPresent([String].self, forKey: .scope) ?? []
        number = try c.decodeIfPresent(String.self, forKey: .number)
        validityDateText = try c.decodeIfPresent(String.self, forKey: .validityDate)
        clientName = try c.decodeIfPresent(CustomerRef.self, forKey: .customers)?.name
        // Legacy rows predate the tax columns being selected; fall back to a
        // tax-free quote rather than failing to decode the whole list.
        subtotal = try c.decodeIfPresent(Double.self, forKey: .subtotal) ?? total
        taxRate = try c.decodeIfPresent(Double.self, forKey: .taxRate) ?? 0
        taxAmount = try c.decodeIfPresent(Double.self, forKey: .taxAmount) ?? 0
    }

    /// True when a tax line should appear on the quote and its PDF.
    var hasTax: Bool { taxRate > 0 && taxAmount > 0 }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let jobSummary, !jobSummary.isEmpty { return jobSummary }
        return "Untitled quote"
    }

    /// "INV-0007" — the allocated number behind the user's own prefix.
    ///
    /// The prefix lives on the business profile rather than on the quote, so
    /// changing it re-labels quotes already issued. That's the deliberate trade:
    /// the alternative stamps a copy of it onto every row, and a trade that
    /// fixes a typo in their prefix wants it fixed everywhere, not from here on.
    func numberText(prefix: String?) -> String? {
        guard let number, !number.isEmpty else { return nil }
        let clean = (prefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? number : clean + number
    }

    /// "Quote INV-0007" — the reference shown to the user and printed on the PDF.
    func numberLabel(prefix: String?) -> String? {
        numberText(prefix: prefix).map { "Quote \($0)" }
    }

    var validityDate: Date? {
        guard let validityDateText else { return nil }
        return QuoteDateFormat.dayOnly.date(from: validityDateText)
    }

    /// True once the validity date has passed (status is left alone; this is
    /// purely how the date reads to the user).
    var isPastValidity: Bool {
        guard let validityDate else { return false }
        return validityDate < Calendar.current.startOfDay(for: Date())
    }

    /// How the status reads today. Nothing ever wrote "expired" to the column —
    /// it was only ever selectable by hand — so a quote whose validity date had
    /// passed went on counting as money in play for as long as the account
    /// existed, quietly inflating the Home total.
    ///
    /// Only an outstanding offer can lapse. Accepted and declined are outcomes
    /// and a date can't undo them; a draft was never sent, so nothing about it
    /// has expired. That leaves sent and viewed — exactly the set the
    /// outstanding figure is built from.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var effectiveStatus: String {
        guard isPastValidity, status == "sent" || status == "viewed" else { return status }
        return "expired"
    }
}
