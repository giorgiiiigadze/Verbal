//
//  ScheduledVisitNotifications.swift
//  Verbal
//
//  Local reminders for visits booked in Upcoming.
//

import Foundation
import UserNotifications

enum ScheduledVisitReminderLeadTime: String, CaseIterable, Identifiable {
    case atTime
    case fifteenMinutes
    case oneHour
    case morningOf

    var id: String { rawValue }

    var label: String {
        switch self {
        case .atTime: return "At the visit time"
        case .fifteenMinutes: return "15 minutes before"
        case .oneHour: return "1 hour before"
        case .morningOf: return "Morning of the visit"
        }
    }

    func reminderDate(for visitDate: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .atTime:
            return visitDate
        case .fifteenMinutes:
            return calendar.date(byAdding: .minute, value: -15, to: visitDate) ?? visitDate
        case .oneHour:
            return calendar.date(byAdding: .hour, value: -1, to: visitDate) ?? visitDate
        case .morningOf:
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: visitDate) ?? visitDate
        }
    }
}

enum ScheduledVisitNotifications {
    static let enabledKey = "scheduledVisitNotificationsEnabled"
    static let leadTimeKey = "scheduledVisitNotificationLeadTime"
    nonisolated static let privateContentKey = "scheduledVisitNotificationPrivateContent"

    nonisolated private static let identifierPrefix = "scheduled-visit-"

    static var remindersEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var leadTime: ScheduledVisitReminderLeadTime {
        let raw = UserDefaults.standard.string(forKey: leadTimeKey)
        return raw.flatMap(ScheduledVisitReminderLeadTime.init(rawValue:)) ?? .atTime
    }

    nonisolated static var privateNotificationContent: Bool {
        UserDefaults.standard.object(forKey: privateContentKey) as? Bool ?? true
    }

    static func schedule(_ visit: ScheduledVisit) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: visit)])

        guard remindersEnabled, visit.date > Date() else { return }
        guard await notificationsAllowed(center: center) else { return }

        let notificationDate = effectiveReminderDate(for: visit)
        guard notificationDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: visit)
        content.body = notificationBody(for: visit)
        content.sound = .default
        content.threadIdentifier = "scheduled-visits"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                         from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: visit),
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    static func rescheduleAll(visits: [ScheduledVisit]) async {
        cancelAll(visits: visits)
        guard remindersEnabled else { return }
        for visit in visits {
            await schedule(visit)
        }
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

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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

    private static func effectiveReminderDate(for visit: ScheduledVisit) -> Date {
        let preferred = leadTime.reminderDate(for: visit.date)
        // If the chosen lead time has already passed for a near-term visit, still
        // remind at the visit time rather than scheduling nothing.
        if preferred <= Date(), visit.date > Date() {
            return visit.date
        }
        return preferred
    }

    nonisolated private static func identifier(for visit: ScheduledVisit) -> String {
        identifierPrefix + visit.id.uuidString
    }

    nonisolated private static func notificationTitle(for visit: ScheduledVisit) -> String {
        guard !privateNotificationContent else {
            return "Upcoming quote reminder"
        }
        // The client first, if there is one: a notification on a lock screen is
        // read at a glance, and "Mrs. Patel" tells the user where they are
        // meant to be in a way "Bathroom rip-out" doesn't.
        let client = visit.clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = visit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = client.isEmpty ? title : client
        guard !subject.isEmpty else { return "Your upcoming quote is waiting for you" }
        return "\(subject) is waiting for you"
    }

    nonisolated private static func notificationBody(for visit: ScheduledVisit) -> String {
        guard !privateNotificationContent else {
            return "Time to record the quote."
        }
        if let note = visit.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return "Time to visit and create the quote. \(note)"
        }
        return "Time to visit and create the quote."
    }
}
