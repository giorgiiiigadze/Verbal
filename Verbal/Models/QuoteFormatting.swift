//
//  QuoteFormatting.swift
//  Verbal
//
//  Shared formatting helpers for quotes: date parsing/rendering, quantity and
//  timestamp labels, and money rounding. Kept together because they're used
//  across the services, the list, the detail screen and the printed document.
//

import Foundation

extension Double {
    /// Money rounded to two decimals, matching the database's `round(x, 2)`.
    var roundedToCents: Double { (self * 100).rounded() / 100 }
}

/// Formatters for Postgres `date` values, which arrive as "yyyy-MM-dd".
enum QuoteDateFormat {
    /// An instant, for range filters. `dayOnly` can't be used for these: a date
    /// with no time in them is read as midnight UTC, which is the wrong boundary
    /// everywhere but one timezone.
    static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Medium, localized rendering for display — e.g. "14 Aug 2026".
    static func display(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// Formats a quote's timestamp as a compact date + time indicator, e.g.
/// "Just now", "4 minutes ago", "Today, 7:45 PM", "Yesterday, 7:45 PM", or "Jul 27".
func quoteDateLabel(_ date: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let seconds = now.timeIntervalSince(date)

    if seconds < 60 { return "Just now" }
    if seconds < 3600 {
        let minutes = Int(seconds / 60)
        return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }

    let time = date.formatted(.dateTime.hour().minute())
    if calendar.isDateInToday(date) { return "Today, \(time)" }
    if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

/// Formats a quantity + unit like "8 each" or "20 meters".
func quantityLabel(_ quantity: Double?, _ unit: String?) -> String? {
    guard let quantity else { return nil }
    let q = quantity.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(quantity))
        : String(format: "%.2f", quantity)
    return [q, unit].compactMap { $0 }.joined(separator: " ")
}
