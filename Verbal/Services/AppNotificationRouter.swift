//
//  AppNotificationRouter.swift
//  Verbal
//
//  Routes local notification taps into the SwiftUI navigation tree.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AppNotificationRouter {
    static let shared = AppNotificationRouter()

    var requestedQuoteId: UUID?
    var requestedVisitId: UUID?
    var hasUnreadVisitReminder = false

    private init() {}

    func openQuote(id: UUID) {
        requestedQuoteId = id
    }

    func clearQuoteRequest(id: UUID) {
        guard requestedQuoteId == id else { return }
        requestedQuoteId = nil
    }

    func openVisit(id: UUID) {
        requestedVisitId = id
        hasUnreadVisitReminder = true
    }

    func clearVisitReminder() {
        hasUnreadVisitReminder = false
        Task {
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.compactMap { notification in
                notification.request.content.userInfo["kind"] as? String == ScheduledVisitNotifications.notificationKind
                    ? notification.request.identifier : nil
            })
        }
    }

    func refreshVisitReminderBadge() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        hasUnreadVisitReminder = delivered.contains {
            $0.request.content.userInfo["kind"] as? String == ScheduledVisitNotifications.notificationKind
        }
    }
}

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            if userInfo["kind"] as? String == QuoteExpiryNotifications.notificationKind,
               let rawQuoteId = userInfo["quoteId"] as? String,
               let quoteId = UUID(uuidString: rawQuoteId) {
                AppNotificationRouter.shared.openQuote(id: quoteId)
            } else if userInfo["kind"] as? String == ScheduledVisitNotifications.notificationKind,
                      let rawVisitId = userInfo["visitId"] as? String,
                      let visitId = UUID(uuidString: rawVisitId) {
                AppNotificationRouter.shared.openVisit(id: visitId)
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.content.userInfo["kind"] as? String == ScheduledVisitNotifications.notificationKind {
            await MainActor.run { AppNotificationRouter.shared.hasUnreadVisitReminder = true }
        }
        return [.banner, .sound]
    }
}
