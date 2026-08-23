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

    private init() {}

    func openQuote(id: UUID) {
        requestedQuoteId = id
    }

    func clearQuoteRequest(id: UUID) {
        guard requestedQuoteId == id else { return }
        requestedQuoteId = nil
    }
}

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard userInfo["kind"] as? String == QuoteExpiryNotifications.notificationKind,
              let rawQuoteId = userInfo["quoteId"] as? String,
              let quoteId = UUID(uuidString: rawQuoteId)
        else { return }

        await MainActor.run {
            AppNotificationRouter.shared.openQuote(id: quoteId)
        }
    }
}
