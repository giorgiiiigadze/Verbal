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
//  Kept in `scheduled_visits` on the server, and mirrored into a per-account
//  cache on the device that the list is actually drawn from. The device copy
//  comes first — a visit booked in a basement is written locally and pushed
//  when there is signal — and `VisitStore` owns both halves.
//
//  It used to live in one UserDefaults key with no user id in it, which sign-out
//  deleted outright: a user who switched accounts lost their booked week and
//  signing back in brought back nothing.
//

import Foundation

struct ScheduledVisit: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// What the visit is: a client, a job, or both — "Mrs. Patel — bathroom".
    /// One field rather than two, because it is written in the ten seconds
    /// after a phone call and a form asks more than that.
    var title: String
    var date: Date
    var phone: String?
    var address: String?
    /// Anything to remember on the way — a gate code, a measurement to take.
    var note: String?
    var recordedQuoteId: UUID?
    var didPromptForMissedVisit: Bool
    /// When this visit was last edited, by whichever device edited it.
    ///
    /// The conflict resolver: two phones on one account both write here, and the
    /// later edit wins. Deliberately the moment of the edit rather than the
    /// moment the server heard about it — a phone that has been offline for
    /// three days arrives last, and arriving last is not the same as being right.
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, date, phone, address, note, recordedQuoteId, didPromptForMissedVisit
        case updatedAt
    }

    init(id: UUID = UUID(),
         title: String,
         date: Date,
         phone: String? = nil,
         address: String? = nil,
         note: String? = nil,
         recordedQuoteId: UUID? = nil,
         didPromptForMissedVisit: Bool = false,
         updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.date = date
        self.phone = phone
        self.address = address
        self.note = note
        self.recordedQuoteId = recordedQuoteId
        self.didPromptForMissedVisit = didPromptForMissedVisit
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        date = try values.decode(Date.self, forKey: .date)
        phone = try values.decodeIfPresent(String.self, forKey: .phone)
        address = try values.decodeIfPresent(String.self, forKey: .address)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        recordedQuoteId = try values.decodeIfPresent(UUID.self, forKey: .recordedQuoteId)
        didPromptForMissedVisit = try values.decodeIfPresent(Bool.self, forKey: .didPromptForMissedVisit) ?? false
        // Absent on rows written before visits were synced. `.distantPast` is
        // the honest answer — the server has never heard of them, so anything
        // it does hold about them is newer.
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// "Today", "Tomorrow", "Thursday", "Tue 2 Sep".
    ///
    /// Named days for the week the user can actually picture, a date beyond it.
    /// The same trade the quote rows make with "Sent 1w ago": say the thing the
    /// reader would otherwise have to work out.
    ///
    /// Split out from `whenText` so a row can set the day and the time
    /// differently — Home draws the time in the visit's own colour and wants
    /// the day quiet beside it, which one string can't express.
    var dayText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: Date()),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return days < 7
            ? date.formatted(.dateTime.weekday(.wide))
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var timeText: String { date.formatted(date: .omitted, time: .shortened) }

    /// "Today · 09:30", "Tomorrow · 14:00", "Thursday · 08:00", "Tue 2 Sep · 08:00".
    var whenText: String { "\(dayText) · \(timeText)" }

    var accessibilityText: String {
        let when = date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
        return "\(title), \(when)"
    }
}
