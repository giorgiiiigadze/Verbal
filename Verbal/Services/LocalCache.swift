//
//  LocalCache.swift
//  Verbal
//
//  Last-known server responses, kept on disk so the app opens with the user's
//  quotes on it instead of a spinner or an error.
//
//  Tradespeople work in basements, lofts and half-built kitchens. Launching
//  without signal used to show "Couldn't load your quotes" to someone whose
//  quotes existed perfectly well — they were just on a server that couldn't be
//  reached. The list is read far more often than it changes, so the last copy
//  is nearly always the right one to show while a fresh one is fetched.
//
//  What is stored is the raw JSON the server sent, not a re-encoded model. The
//  same bytes through the same decoder round-trip exactly, so no model needs an
//  Encodable conformance and the cache cannot drift from the network shape as
//  columns are added.
//

import Foundation
import Supabase

/// Deliberately off the main actor. The project defaults every type onto it,
/// which quietly made these file reads main-thread work no matter where they
/// were called from — a background restore would hop straight back and block
/// the very launch it was meant to keep clear. Nothing here touches shared
/// state; it is reads and writes against the file system.
nonisolated enum LocalCache {
    enum Key {
        case quotes
        case rateCard
        case businessProfile
        /// One file per quote. Line items are fetched a quote at a time as rows
        /// come into view, so they're stored the same way rather than as one
        /// blob that every prefetch would have to rewrite.
        case lineItems(quoteID: UUID)
        /// The words the quote was built from, per quote. Unlike everything
        /// else here this is stored as a plain JSON string rather than the
        /// server's rows: it is also written at the moment a quote is recorded,
        /// when there is no server response to keep.
        case transcript(quoteID: UUID)
        /// The business logo's bytes, not JSON. Kept so a quote shared from a
        /// basement still prints the user's mark on it — the profile row was
        /// already cached for exactly that reason, and a letterhead that loses
        /// its logo offline is half a letterhead.
        case businessLogo
        /// The signed-in identity from Google: name and avatar URL. Everything
        /// else here survives a launch with no signal, and without this the one
        /// screen that shows who you are is the one that forgets.
        case profile
        /// The avatar's bytes, alongside the row that names it.
        case avatar
        /// Booked visits, plus what still has to be pushed about them. Unlike
        /// everything else here this is not only a copy of a server response:
        /// a visit booked with no signal exists here and nowhere else until the
        /// phone finds some, so this file is the original, not the cache.
        case scheduledVisits

        var filename: String {
            switch self {
            case .quotes: return "quotes"
            case .rateCard: return "rateCard"
            case .businessProfile: return "businessProfile"
            case .profile: return "profile"
            case .avatar: return "avatar"
            case .scheduledVisits: return "scheduledVisits"
            case .lineItems(let quoteID): return "lineItems-\(quoteID.uuidString)"
            case .transcript(let quoteID): return "transcript-\(quoteID.uuidString)"
            case .businessLogo: return "businessLogo"
            }
        }
    }

    /// Kept per account. One shared file would hand the previous user's quotes
    /// and client details to whoever signs in next on the same phone.
    private static func directory(for userID: UUID) -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return base.appendingPathComponent("Cache/\(userID.uuidString)", isDirectory: true)
    }

    static func save(_ data: Data, for key: Key, userID: UUID) {
        guard let directory = directory(for: userID) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // This holds business details and customer names and addresses, so it
        // stays unreadable until the phone has been unlocked once since boot.
        try? data.write(
            to: directory.appendingPathComponent(key.filename),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    static func load<T: Decodable>(_ type: T.Type, for key: Key, userID: UUID) -> T? {
        guard let directory = directory(for: userID),
              let data = try? Data(contentsOf: directory.appendingPathComponent(key.filename))
        else { return nil }
        // Decoded exactly as the live response would have been.
        return try? PostgrestClient.Configuration.jsonDecoder.decode(type, from: data)
    }

    /// The stored bytes as they were written, for things that aren't JSON.
    static func loadData(for key: Key, userID: UUID) -> Data? {
        guard let directory = directory(for: userID) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(key.filename))
    }

    /// Whether something is already stored, without paying to decode it.
    static func exists(for key: Key, userID: UUID) -> Bool {
        guard let directory = directory(for: userID) else { return false }
        return FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(key.filename).path
        )
    }

    /// Drop one stored item.
    static func clear(key: Key, userID: UUID) {
        guard let directory = directory(for: userID) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key.filename))
    }

    /// Drop the files belonging to one quote. A deleted quote leaves its rows
    /// behind on disk otherwise, and a transcript is a recording of someone
    /// talking about a customer's house — it should not outlive the quote it
    /// was taken for.
    static func clear(quoteID: UUID, userID: UUID) {
        guard let directory = directory(for: userID) else { return }
        for key in [Key.lineItems(quoteID: quoteID), .transcript(quoteID: quoteID)] {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(key.filename)
            )
        }
    }

    /// Drop everything held for an account. Called when it signs out or is
    /// swapped, so nothing of one user's survives into the next one's session.
    static func clear(userID: UUID) {
        guard let directory = directory(for: userID) else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
