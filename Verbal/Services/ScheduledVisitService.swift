//
//  ScheduledVisitService.swift
//  Verbal
//
//  What the app asks Supabase about booked visits.
//
//  Three calls, and no more than three on purpose: the whole list is a handful
//  of rows, so it is pushed and pulled whole rather than diffed field by field.
//  `VisitStore` decides what needs saying; this file only says it.
//

import Foundation
import Supabase

enum ScheduledVisitService {
    private static var client: SupabaseClient { SupabaseManager.client }

    /// One row as the table holds it. Kept separate from `ScheduledVisit` so
    /// the column names live here rather than leaking into a model the views
    /// read, and so a column added later can't quietly break the local cache's
    /// encoding.
    private struct Row: Codable {
        let id: UUID
        let title: String
        let scheduledAt: Date
        let phone: String?
        let address: String?
        let note: String?
        let recordedQuoteId: UUID?
        let didPromptForMissedVisit: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, phone, address, note
            case scheduledAt = "scheduled_at"
            case recordedQuoteId = "recorded_quote_id"
            case didPromptForMissedVisit = "did_prompt_for_missed_visit"
            case updatedAt = "updated_at"
        }

        var visit: ScheduledVisit {
            ScheduledVisit(id: id,
                           title: title,
                           date: scheduledAt,
                           phone: phone,
                           address: address,
                           note: note,
                           recordedQuoteId: recordedQuoteId,
                           didPromptForMissedVisit: didPromptForMissedVisit,
                           updatedAt: updatedAt)
        }
    }

    /// The same row with the owner on it, for writes.
    private struct Payload: Encodable {
        let id: UUID
        let userId: UUID
        let title: String
        let scheduledAt: Date
        let phone: String?
        let address: String?
        let note: String?
        let recordedQuoteId: UUID?
        let didPromptForMissedVisit: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, phone, address, note
            case userId = "user_id"
            case scheduledAt = "scheduled_at"
            case recordedQuoteId = "recorded_quote_id"
            case didPromptForMissedVisit = "did_prompt_for_missed_visit"
            case updatedAt = "updated_at"
        }

        init(_ visit: ScheduledVisit, userID: UUID) {
            id = visit.id
            userId = userID
            title = visit.title
            scheduledAt = visit.date
            phone = visit.phone
            address = visit.address
            note = visit.note
            recordedQuoteId = visit.recordedQuoteId
            didPromptForMissedVisit = visit.didPromptForMissedVisit
            updatedAt = visit.updatedAt
        }
    }

    private static func currentUserID() throws -> UUID {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        return userID
    }

    static func fetch() async throws -> [ScheduledVisit] {
        let userID = try currentUserID()
        let response: PostgrestResponse<[Row]> = try await client
            .from("scheduled_visits")
            .select()
            .eq("user_id", value: userID)
            .order("scheduled_at", ascending: true)
            .execute()
        return response.value.map(\.visit)
    }

    /// Write visits the device has changed. Keyed on the id the device
    /// generated, so a push that is retried after a timeout updates the row it
    /// made the first time instead of booking the visit twice.
    ///
    /// The owner is passed in rather than read from the session here. A push
    /// that started before an account switch and landed after it would
    /// otherwise stamp the *new* user onto the previous user's visits, filing
    /// one person's clients under another. Named explicitly, the row carries
    /// the id it was written for, and `with check (auth.uid() = user_id)`
    /// refuses it outright if the session has moved on.
    static func upsert(_ visits: [ScheduledVisit], userID: UUID) async throws {
        guard !visits.isEmpty else { return }
        try await client
            .from("scheduled_visits")
            .upsert(visits.map { Payload($0, userID: userID) }, onConflict: "id")
            .execute()
    }

    static func delete(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await client
            .from("scheduled_visits")
            .delete()
            .in("id", values: ids)
            .execute()
    }
}
