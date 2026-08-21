//
//  ScheduledVisitNotifications.swift
//  Verbal
//
//  Local reminders for visits booked in Upcoming.
//

import Foundation
import UserNotifications

enum ScheduledVisitNotifications {
    nonisolated private static let identifierPrefix = "scheduled-visit-"

    static func schedule(_ visit: ScheduledVisit) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: visit)])

        guard visit.date > Date() else { return }
        guard await notificationsAllowed(center: center) else { return }

        let content = UNMutableNotificationContent()
        content.title = visit.title
        content.body = notificationBody(for: visit)
        content.sound = .default
        content.threadIdentifier = "scheduled-visits"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                         from: visit.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: visit),
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    static func cancel(_ visit: ScheduledVisit) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: visit)])
    }

    static func cancelAll(visits: [ScheduledVisit]) {
        let identifiers = visits.map(identifier(for:))
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
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

    nonisolated private static func identifier(for visit: ScheduledVisit) -> String {
        identifierPrefix + visit.id.uuidString
    }

    nonisolated private static func notificationBody(for visit: ScheduledVisit) -> String {
        if let note = visit.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return "Time to visit and create the quote. \(note)"
        }
        return "Time to visit and create the quote."
    }
}
