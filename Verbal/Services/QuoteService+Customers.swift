//
//  QuoteService+Customers.swift
//  Verbal
//
//  Who a quote is for. One customer row per name, reused rather than
//  duplicated — which is what makes renaming one fix every quote at once.
//

import Foundation
import Supabase

extension QuoteService {
    /// Escapes the characters `ILIKE` treats as wildcards, so a client name is
    /// matched literally. Without this, a name holding `%`, `_` or `*` (which
    /// PostgREST rewrites to `%`) matches some unrelated customer and the quote
    /// is silently filed under the wrong person.
    private static func escapingLikeWildcards(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "%" || character == "_" || character == "*" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// Resolve a typed client name to a customer row, reusing an existing one
    /// with the same name (case-insensitive) so repeat customers don't pile up
    /// as duplicates. Returns nil for an empty name.
    static func customerID(named name: String, userID: UUID) async throws -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        struct Row: Decodable { let id: UUID }
        let existing: [Row] = try await client
            .from("customers")
            .select("id")
            .eq("user_id", value: userID)
            .ilike("name", pattern: escapingLikeWildcards(trimmed))
            .limit(1)
            .execute()
            .value
        if let found = existing.first { return found.id }

        struct CustomerInsert: Encodable {
            let userId: UUID
            let name: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case name
            }
        }
        let created: Row = try await client
            .from("customers")
            .insert(CustomerInsert(userId: userID, name: trimmed), returning: .representation)
            .select("id")
            .single()
            .execute()
            .value
        return created.id
    }

    /// Names the user has quoted for before — powers suggestions on the client field.
    static func customerNames() async throws -> [String] {
        guard let userID = client.auth.currentUser?.id else { return [] }
        struct Row: Decodable { let name: String? }
        let rows: [Row] = try await client
            .from("customers")
            .select("name")
            .eq("user_id", value: userID)
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value
        return rows.compactMap(\.name).filter { !$0.isEmpty }
    }

    /// Where a client is, if they have ever been given an address.
    ///
    /// Matched on the name the same way `renameClient` matches, so the row
    /// found here is the row a rename would move — the app has no client id to
    /// ask with, because `Client` is derived from the quote list rather than
    /// fetched.
    static func customerAddress(named name: String) async throws -> String? {
        guard let userID = client.auth.currentUser?.id else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        struct Row: Decodable { let address: String? }
        let response: PostgrestResponse<[Row]> = try await client
            .from("customers")
            .select("address")
            .eq("user_id", value: userID)
            .ilike("name", pattern: escapingLikeWildcards(trimmed))
            .limit(1)
            .execute()
        let address = response.value.first?.address?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (address?.isEmpty ?? true) ? nil : address
    }

    /// Give a client an address, or take it away.
    ///
    /// Written to every row of theirs rather than the first: two rows can share
    /// a name until the next rename merges them, and setting the address on
    /// only one of those would make it appear and disappear depending on which
    /// one the read happened to land on. An empty string clears it, so the
    /// editor can be used to remove an address as well as correct one.
    static func setCustomerAddress(_ address: String?, forClientNamed name: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmed = address?.trimmingCharacters(in: .whitespacesAndNewlines)

        struct Payload: Encodable { let address: String? }
        try await client
            .from("customers")
            .update(Payload(address: (trimmed?.isEmpty ?? true) ? nil : trimmed))
            .eq("user_id", value: userID)
            .ilike("name", pattern: escapingLikeWildcards(trimmedName))
            .execute()
    }

    /// Rename a client on every quote of theirs at once, merging them into an
    /// existing person when the new name is already taken.
    ///
    /// The name a client is filed under is whatever was said into the mic, and
    /// a misheard one could only be corrected quote by quote — which is also
    /// how "Tamar Beridze" and "Tamar Beridge" became two clients. So the merge
    /// isn't a separate feature: repointing the quotes and dropping the emptied
    /// row is what renaming onto an existing name has to mean.
    ///
    /// A change of spelling or capitalisation alone is not a merge — that is
    /// the same row being corrected, so the survivor is looked for among rows
    /// other than the ones being renamed.
    static func renameClient(from oldName: String, to newName: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let old = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty else { return }

        struct Row: Decodable { let id: UUID }
        struct NamePayload: Encodable { let name: String }
        struct CustomerPayload: Encodable {
            let customerId: UUID
            enum CodingKeys: String, CodingKey { case customerId = "customer_id" }
        }

        func rows(named name: String) async throws -> [Row] {
            // Typed on the response rather than on a decoded array, the way
            // `fetchQuotes` does it: inferring the row type through `.value`
            // instead picks an `execute()` the compiler reads as neither
            // throwing nor suspending, and it warns that the `try await` here
            // is doing nothing.
            let response: PostgrestResponse<[Row]> = try await client
                .from("customers")
                .select("id")
                .eq("user_id", value: userID)
                .ilike("name", pattern: escapingLikeWildcards(name))
                .execute()
            return response.value
        }

        let renaming = try await rows(named: old).map(\.id)
        guard !renaming.isEmpty else { return }
        let survivor = try await rows(named: new).map(\.id).first { !renaming.contains($0) }

        if let survivor {
            // Every quote of theirs moves to the person who keeps the name,
            // before the emptied rows go — an order that leaves no quote
            // pointing at a customer that no longer exists, even if the second
            // call never happens.
            try await client
                .from("quotes")
                .update(CustomerPayload(customerId: survivor))
                .eq("user_id", value: userID)
                .in("customer_id", values: renaming)
                .execute()
            // The survivor takes the spelling that was just typed, so correcting
            // the capitalisation of a name that already exists still corrects it.
            try await client
                .from("customers")
                .update(NamePayload(name: new))
                .eq("user_id", value: userID)
                .eq("id", value: survivor)
                .execute()
            try await client
                .from("customers")
                .delete()
                .eq("user_id", value: userID)
                .in("id", values: renaming)
                .execute()
        } else {
            try await client
                .from("customers")
                .update(NamePayload(name: new))
                .eq("user_id", value: userID)
                .in("id", values: renaming)
                .execute()
        }
    }

    /// Link an existing quote to a client by name (used when editing).
    static func setClient(quoteId: UUID, name: String) async throws {
        guard let userID = client.auth.currentUser?.id else {
            throw QuoteError.notSignedIn
        }
        let customerId = try await customerID(named: name, userID: userID)
        struct Payload: Encodable {
            let customerId: UUID?
            enum CodingKeys: String, CodingKey { case customerId = "customer_id" }
        }
        try await client
            .from("quotes")
            .update(Payload(customerId: customerId))
            .eq("id", value: quoteId)
            .execute()
    }
}
