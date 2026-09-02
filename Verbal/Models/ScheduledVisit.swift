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
    /// What the visit is called — "Bathroom rip-out", "Roof survey".
    ///
    /// It used to be the client, the job and the label all at once, which is
    /// why old rows read like names: a visit called "Mrs. Patel" is still a
    /// perfectly good name for a visit, so nothing had to be rewritten when the
    /// client moved into `clientName` below.
    var title: String
    /// Who the visit is for. Free text, because a visit is booked before there
    /// is a customer row to point at — often before the job is even won.
    var clientName: String?
    /// When the visit starts.
    var date: Date
    /// How long it is booked for. Never zero: a visit with no length is a point
    /// on the calendar, and two of those an hour apart look the same as two a
    /// day apart.
    var durationMinutes: Int
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
        case id, title, clientName, date, durationMinutes, phone, address, note
        case recordedQuoteId, didPromptForMissedVisit
        case updatedAt
    }

    init(id: UUID = UUID(),
         title: String,
         clientName: String? = nil,
         date: Date,
         durationMinutes: Int = ScheduledVisit.defaultDurationMinutes,
         phone: String? = nil,
         address: String? = nil,
         note: String? = nil,
         recordedQuoteId: UUID? = nil,
         didPromptForMissedVisit: Bool = false,
         updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.clientName = clientName
        self.date = date
        self.durationMinutes = max(ScheduledVisit.minimumDurationMinutes, durationMinutes)
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
        clientName = try values.decodeIfPresent(String.self, forKey: .clientName)
        date = try values.decode(Date.self, forKey: .date)
        // Absent on visits booked before a visit had a length. An hour is the
        // length of nearly every survey, and it is editable.
        durationMinutes = max(ScheduledVisit.minimumDurationMinutes,
                              try values.decodeIfPresent(Int.self, forKey: .durationMinutes)
                                  ?? ScheduledVisit.defaultDurationMinutes)
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

    /// An hour, which is how long a survey takes.
    static let defaultDurationMinutes = 60
    /// A quarter of an hour. Short enough for a doorstep look, long enough that
    /// a mis-drag on the end time can't collapse a visit to nothing.
    static let minimumDurationMinutes = 15

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// When the visit is booked until.
    var endDate: Date { date.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    /// The person this visit is for, lowercased, for matching against client
    /// records.
    ///
    /// Falls back to the title, which is where the client's name lived before
    /// it had a field of its own — old visits still find their client.
    var clientKey: String {
        let named = clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (named.isEmpty ? title : named)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// "1h 30min", "45min", "2h". The quiet label beside the time range —
    /// the answer to "how long am I there for" without the reader subtracting
    /// one clock time from another.
    var durationText: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)min"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)min"
        }
    }

    var endTimeText: String { endDate.formatted(date: .omitted, time: .shortened) }

    /// "09:30 – 11:00".
    var timeRangeText: String { "\(timeText) – \(endTimeText)" }

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
        let who = clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subject = who.isEmpty ? title : "\(title), for \(who)"
        return "\(subject), \(when), \(durationText)"
    }
}
