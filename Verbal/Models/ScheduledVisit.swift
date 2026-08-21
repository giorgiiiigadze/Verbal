//
//  ScheduledVisit.swift
//  Verbal
//
//  A job the user has booked in but not quoted yet — Tuesday at Mrs. Patel's,
//  the roof survey on the 23rd. The thing a tradesperson writes on the back of
//  their hand between the phone call and the visit.
//
//  Deliberately not a quote. A quote has a customer row, a number, line items
//  and a total, and none of that exists yet at the moment the visit is booked;
//  forcing an empty draft into the quotes table to hold a date would put a
//  £0 quote in the list, in the count, and in the client's history.
//
//  Held on the device rather than on the server, on purpose for now: it is a
//  note-to-self with a date on it, and it earns its way to a table once it has
//  proved it is used. The cost is that it doesn't follow the user to a second
//  phone — which is why nothing else depends on it.
//

import Foundation

struct ScheduledVisit: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// What the visit is: a client, a job, or both — "Mrs. Patel — bathroom".
    /// One field rather than two, because it is written in the ten seconds
    /// after a phone call and a form asks more than that.
    var title: String
    var date: Date
    var address: String?
    /// Anything to remember on the way — a gate code, a measurement to take.
    var note: String?
    var recordedQuoteId: UUID?
    var didPromptForMissedVisit: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, date, address, note, recordedQuoteId, didPromptForMissedVisit
    }

    init(id: UUID = UUID(),
         title: String,
         date: Date,
         address: String? = nil,
         note: String? = nil,
         recordedQuoteId: UUID? = nil,
         didPromptForMissedVisit: Bool = false) {
        self.id = id
        self.title = title
        self.date = date
        self.address = address
        self.note = note
        self.recordedQuoteId = recordedQuoteId
        self.didPromptForMissedVisit = didPromptForMissedVisit
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        date = try values.decode(Date.self, forKey: .date)
        address = try values.decodeIfPresent(String.self, forKey: .address)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        recordedQuoteId = try values.decodeIfPresent(UUID.self, forKey: .recordedQuoteId)
        didPromptForMissedVisit = try values.decodeIfPresent(Bool.self, forKey: .didPromptForMissedVisit) ?? false
    }

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// "Today · 09:30", "Tomorrow · 14:00", "Thursday · 08:00", "Tue 2 Sep · 08:00".
    ///
    /// Named days for the week the user can actually picture, a date beyond it.
    /// The same trade the quote rows make with "Sent 1w ago": say the thing the
    /// reader would otherwise have to work out.
    var whenText: String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow · \(time)" }

        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: Date()),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let day = days < 7
            ? date.formatted(.dateTime.weekday(.wide))
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day) · \(time)"
    }

    var accessibilityText: String {
        let when = date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
        return "\(title), \(when)"
    }

    // MARK: - Storage

    private static let key = "scheduledVisits"

    /// Everything still active, soonest first. Recorded visits stay through
    /// their booked day. Missed visits stay until the user answers the one-time
    /// follow-up prompt.
    static func load() -> [ScheduledVisit] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode([ScheduledVisit].self, from: data)
        else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let upcoming = stored
            .filter { visit in
                if visit.recordedQuoteId != nil {
                    return calendar.startOfDay(for: visit.date) >= today
                }
                return !visit.didPromptForMissedVisit
            }
            .sorted { $0.date < $1.date }

        // Only rewrite when the prune actually removed something, so a plain
        // read of an unchanged list isn't a write.
        if upcoming.count != stored.count { save(upcoming) }
        return upcoming
    }

    static func save(_ visits: [ScheduledVisit]) {
        let sorted = visits.sorted { $0.date < $1.date }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Cleared with the account. The titles are client names, so they belong to
    /// whoever was signed in, not to the handset — the same reason the quote
    /// cache is wiped on sign-out.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
