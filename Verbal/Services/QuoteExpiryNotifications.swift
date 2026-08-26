//
//  QuoteExpiryNotifications.swift
//  Verbal
//
//  Local reminders for sent quotes that are about to expire.
//

import Foundation
import UserNotifications

enum QuoteExpiryNotifications {
    nonisolated static let notificationKind = "quoteExpiry"
    nonisolated private static let identifierPrefix = "quote-expiry-"

    static func schedule(_ quote: QuoteSummary) async {
        await schedule(id: quote.id,
                       title: quote.displayTitle,
                       status: quote.effectiveStatus,
                       validityDate: quote.validityDate)
    }

    static func schedule(id: UUID, title: String, status: String, validityDate: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: id)])

        guard shouldNotify(status: status, validityDate: validityDate),
              let notificationDate = reminderDate(for: validityDate),
              notificationDate > Date(),
              await notificationsAllowed(center: center)
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "Quote expiring soon"
        content.body = notificationBody(title: title, validityDate: validityDate)
        content.sound = .default
        content.threadIdentifier = "quote-expiry"
        content.userInfo = [
            "kind": notificationKind,
            "quoteId": id.uuidString
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                         from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: id),
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    static func rescheduleAll(quotes: [QuoteSummary]) async {
        await cancelAllPending()
        for quote in quotes {
            await schedule(quote)
        }
    }

    static func cancel(_ quote: QuoteSummary) {
        cancel(id: quote.id)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: id)])
    }

    private static func shouldNotify(status: String, validityDate: Date?) -> Bool {
        guard ScheduledVisitNotifications.remindersEnabled,
              validityDate != nil,
              status == "sent" || status == "viewed"
        else { return false }
        return true
    }

    private static func reminderDate(for validityDate: Date?) -> Date? {
        guard let validityDate else { return nil }
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: validityDate) ?? validityDate

        if morning > Date() { return morning }

        // If the quote is still valid but the morning reminder time has passed,
        // send the reminder soon instead of skipping it entirely.
        let validityDay = calendar.startOfDay(for: validityDate)
        if validityDay >= calendar.startOfDay(for: Date()) {
            return Date().addingTimeInterval(5 * 60)
        }
        return nil
    }

    private static func cancelAllPending() async {
        let center = UNUserNotificationCenter.current()
        let requests = await pendingRequests(center: center)
        let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func pendingRequests(center: UNUserNotificationCenter) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private static func notificationsAllowed(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    nonisolated private static func identifier(for id: UUID) -> String {
        identifierPrefix + id.uuidString
    }

    private static func notificationBody(title: String, validityDate: Date?) -> String {
        guard !ScheduledVisitNotifications.privateNotificationContent else {
            if validityDate != nil {
                return "A sent quote is close to its valid-until date."
            }
            return "A sent quote is about to expire."
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "This quote" : trimmed
        if let validityDate {
            return "\(name) is valid until \(QuoteDateFormat.display(validityDate)). Follow up before it expires."
        }
        return "\(name) is about to expire. Follow up while it is still valid."
    }
}
