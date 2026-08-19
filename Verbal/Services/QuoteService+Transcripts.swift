//
//  QuoteService+Transcripts.swift
//  Verbal
//
//  What was said, kept so a quote can be read back against its own words.
//

import Foundation
import Supabase

extension QuoteService {
    /// Fetch the transcript text saved with a quote.
    static func fetchTranscript(quoteId: UUID) async throws -> String? {
        struct Row: Decodable { let text: String? }
        let rows: [Row] = try await client
            .from("transcripts")
            .select("text")
            .eq("quote_id", value: quoteId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        let text = rows.first?.text
        if let text { cacheTranscript(text, quoteId: quoteId) }
        return text
    }

    /// The transcript as it was last seen, for when the network can't be
    /// reached. Read straight from disk rather than held in memory: it is
    /// wanted only when the sheet is opened, and some of these are long.
    static func cachedTranscript(quoteId: UUID) -> String? {
        guard let userID = client.auth.currentUser?.id else { return nil }
        return LocalCache.load(String.self, for: .transcript(quoteID: quoteId), userID: userID)
    }

    /// Store the transcripts of every quote that hasn't got one on disk yet, in
    /// a single request. Caching on create covers quotes made from here on, and
    /// caching on open covers whatever the user happens to visit — neither
    /// reaches the quotes already on the account, which offline showed "No
    /// transcript saved." for work the user had dictated themselves. Run at
    /// launch, so going offline later finds the whole list readable.
    static func cacheMissingTranscripts(for quoteIDs: [UUID]) async {
        guard let userID = client.auth.currentUser?.id else { return }
        let missing = quoteIDs.filter {
            !LocalCache.exists(for: .transcript(quoteID: $0), userID: userID)
        }
        guard !missing.isEmpty else { return }

        struct Row: Decodable {
            let quoteId: UUID
            let text: String?
            enum CodingKeys: String, CodingKey {
                case quoteId = "quote_id"
                case text
            }
        }
        guard let rows: [Row] = try? await client
            .from("transcripts")
            .select("quote_id, text")
            .in("quote_id", values: missing)
            .order("created_at", ascending: true)
            .execute()
            .value
        else { return }

        // Oldest first, so where a quote carries more than one transcript the
        // newest is what's left standing — the same one a single fetch picks.
        var newest: [UUID: String] = [:]
        for row in rows {
            if let text = row.text, !text.isEmpty { newest[row.quoteId] = text }
        }
        for (quoteID, text) in newest {
            cacheTranscript(text, quoteId: quoteID)
        }
    }

    /// Keep a copy of the words a quote was built from. Called both when one is
    /// fetched and when one is first recorded — the second is what matters, as
    /// it means a quote dictated in a basement can be reread there without the
    /// user ever having opened it somewhere with signal.
    /// Internal, not private: saving and duplicating a quote both write the
    /// transcript they just stored into the cache, and they live next door.
    static func cacheTranscript(_ text: String, quoteId: UUID) {
        guard let userID = client.auth.currentUser?.id,
              let data = try? JSONEncoder().encode(text) else { return }
        LocalCache.save(data, for: .transcript(quoteID: quoteId), userID: userID)
    }
}
