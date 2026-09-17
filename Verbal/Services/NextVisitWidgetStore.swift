//
//  NextVisitWidgetStore.swift
//  Verbal
//
//  The widget has no authenticated session of its own. The app therefore
//  publishes a deliberately small, local snapshot whenever bookings change.
//

import Foundation
import WidgetKit

enum NextVisitWidgetStore {
    static let appGroup = "group.com.giorgi.verbal"
    static let snapshotKey = "nextVisitWidgetSnapshot"

    struct Snapshot: Codable {
        let id: UUID
        let title: String
        let clientName: String?
        let date: Date
        let endDate: Date
        let address: String?

        init(_ visit: ScheduledVisit) {
            id = visit.id
            title = visit.title
            clientName = visit.clientName
            date = visit.date
            endDate = visit.endDate
            address = visit.address
        }
    }

    struct Payload: Codable { let visits: [Snapshot] }

    @MainActor
    static func publish(from visits: [ScheduledVisit]) {
        let now = Date()
        let upcoming = visits.filter { $0.endDate >= now && $0.recordedQuoteId == nil }
            .prefix(4).map(Snapshot.init)
        let data = try? JSONEncoder().encode(Payload(visits: upcoming))
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "NextVisitWidget")
    }
}
