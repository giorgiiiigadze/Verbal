//
//  VisitStore.swift
//  Verbal
//
//  The booked visits of whoever is signed in — the list Home's Upcoming section
//  is drawn from, the file it survives a launch in, and the sync that keeps it
//  and `scheduled_visits` telling the same story.
//
//  Two rules shape everything here.
//
//  The device writes first. A visit is booked in the ten seconds after a phone
//  call, and often in a basement — the row goes into memory and onto disk
//  immediately, and the server hears about it whenever there is signal. Nothing
//  the user does waits on a network call, so nothing they do can fail because
//  of one.
//
//  The list is never behind a fetch. `attach` is synchronous: it reads the
//  cache and publishes, so Home paints its rows on the first frame exactly as
//  it did when this was a UserDefaults key. A pull happens afterwards and
//  changes the list only if it actually has something to say.
//

import Foundation

@MainActor
@Observable
final class VisitStore {
    /// Everything still active for this account, soonest first.
    private(set) var visits: [ScheduledVisit] = []
    /// An empty visit list only becomes an empty-state answer after the first
    /// sync attempt. Before then, a new device cannot distinguish "none" from
    /// "not fetched yet".
    private(set) var hasCompletedInitialSync = false

    private let network: NetworkMonitor

    /// The account these belong to. Nil between sign-out and the next sign-in,
    /// and the reason a second account can't see the first one's bookings.
    private var userID: UUID?

    /// Rows the device has changed that the server hasn't been told about.
    private var unsynced: Set<UUID> = []

    /// Rows deleted here and not yet deleted there. Without these a delete made
    /// offline would be undone by the next pull, which would hand the user back
    /// a visit they had already cancelled.
    private var tombstones: [Tombstone] = []

    private var isSyncing = false
    private var wantsAnotherPass = false

    init(network: NetworkMonitor) {
        self.network = network
    }

    // MARK: - Stored shape

    private struct Tombstone: Codable, Equatable {
        let id: UUID
        let deletedAt: Date
    }

    private struct Cache: Codable {
        var visits: [ScheduledVisit] = []
        var unsynced: [UUID] = []
        var tombstones: [Tombstone] = []
    }

    /// Our own coders rather than `LocalCache.load`'s. That one decodes with
    /// Postgrest's decoder because everything else in the cache is a server
    /// response kept byte-for-byte; this file is written here, so it is read
    /// here too.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Lifecycle

    /// Bind to an account and publish its visits, without touching the network.
    ///
    /// Called from `SessionStore.restoreFromDisk`, which runs before anything is
    /// drawn. Re-binding to the account already loaded is a no-op: bootstrap
    /// runs on every token refresh, and re-reading the file each time would
    /// throw away edits made since.
    func attach(userID: UUID) {
        guard self.userID != userID else { return }
        self.userID = userID
        hasCompletedInitialSync = false

        // The legacy cache predates account-scoped storage. Once an account
        // with its own cache opens the app, it claims that old key too, so it
        // can never later be adopted by a different account on this phone.
        let storedCache = loadCache(userID: userID)
        if storedCache != nil { claimLegacyVisits(for: userID) }
        var cache = storedCache ?? adoptLegacyVisits(for: userID)
        prune(&cache)
        apply(cache)
        save()
    }

    /// Let go of the current account's visits.
    ///
    /// `preservingCache` keeps this account's visit file after the rest of the
    /// account cache has been wiped. The file is still written under that
    /// account's id, so a second account cannot see it; the original account can
    /// repaint Upcoming immediately on the next sign-in, and any pending edits
    /// still push when signal returns.
    ///
    /// Account deletion passes `false`: there is nothing left to push to.
    func detach(preservingCache: Bool) {
        defer {
            userID = nil
            visits = []
            unsynced = []
            tombstones = []
            hasCompletedInitialSync = false
        }
        guard preservingCache, let userID else { return }

        let cache = Cache(visits: visits,
                          unsynced: Array(unsynced),
                          tombstones: tombstones)
        guard !cache.visits.isEmpty || !cache.tombstones.isEmpty else { return }
        write(cache, userID: userID)
    }

    /// Push everything outstanding while the session can still authenticate.
    ///
    /// Called by `SessionStore.signOut` *before* Supabase drops the token —
    /// afterwards there is no session to write with, and the rows would have to
    /// wait on disk for the next sign-in instead.
    func flushPending() async {
        guard hasPendingWork else { return }
        await sync()
    }

    private var hasPendingWork: Bool { !unsynced.isEmpty || !tombstones.isEmpty }

    /// Drop what the list is finished with, without touching the network.
    ///
    /// Home calls this every time it appears, for the same reason it used to
    /// re-read storage there: a phone left open overnight would otherwise still
    /// be offering yesterday. It has to be separate from `sync`, because `sync`
    /// does nothing at all with no signal and this still has to happen.
    func refresh() {
        guard userID != nil else { return }
        var cache = Cache(visits: visits,
                          unsynced: Array(unsynced),
                          tombstones: tombstones)
        prune(&cache)
        guard cache.visits != visits else { return }
        apply(cache)
        save()
        Task { await sync() }
    }

    // MARK: - Operations
    //
    // One per mutation Home makes. Each stamps the edit's own time, marks the
    // row as owing the server an update, saves, and asks for a sync — which
    // does nothing at all if there is no signal.

    /// A new booking, or a correction to one.
    func addOrUpdate(_ visit: ScheduledVisit) {
        var edited = visit
        edited.updatedAt = .now
        if let index = visits.firstIndex(where: { $0.id == edited.id }) {
            visits[index] = edited
        } else {
            visits.append(edited)
        }
        visits.sort { $0.date < $1.date }
        // A booking re-made after being cancelled offline: drop the tombstone,
        // or the pending delete would take the new one down with it.
        tombstones.removeAll { $0.id == edited.id }
        unsynced.insert(edited.id)
        saveAndSync()
    }

    func remove(_ visit: ScheduledVisit) {
        visits.removeAll { $0.id == visit.id }
        markDeleted(visit.id)
        saveAndSync()
    }

    /// The visit has become a quote.
    func markRecorded(_ visit: ScheduledVisit, quoteId: UUID) {
        guard let index = visits.firstIndex(where: { $0.id == visit.id }) else { return }
        visits[index].recordedQuoteId = quoteId
        visits[index].didPromptForMissedVisit = false
        visits[index].updatedAt = .now
        unsynced.insert(visit.id)
        saveAndSync()
    }

    /// Release visits pointing at a quote that has been deleted, and hand back
    /// the ones that changed so their reminders can be put back.
    @discardableResult
    func unlink(fromDeletedQuote quoteId: UUID) -> [ScheduledVisit] {
        let indices = visits.indices.filter { visits[$0].recordedQuoteId == quoteId }
        guard !indices.isEmpty else { return [] }
        for index in indices {
            visits[index].recordedQuoteId = nil
            visits[index].updatedAt = .now
            unsynced.insert(visits[index].id)
        }
        saveAndSync()
        return indices.map { visits[$0] }
    }

    /// The user has answered the one-time "did this go ahead?" prompt, and the
    /// visit is finished with either way.
    func markPromptedAndClear(_ visit: ScheduledVisit) {
        visits.removeAll { $0.id == visit.id }
        markDeleted(visit.id)
        saveAndSync()
    }

    /// A row the server was never told about still gets a tombstone. It may have
    /// reached the server on an earlier pass, and a delete for a row that isn't
    /// there costs nothing — where a missed delete hands back a cancelled visit.
    private func markDeleted(_ id: UUID) {
        unsynced.remove(id)
        if !tombstones.contains(where: { $0.id == id }) {
            tombstones.append(Tombstone(id: id, deletedAt: .now))
        }
    }

    private func saveAndSync() {
        save()
        Task { await sync() }
    }

    // MARK: - Sync

    /// Reconcile the device and the server, in that order: pull, merge, then
    /// say what is still ours to say.
    ///
    /// Pulling first is what makes the merge honest. Pushing blind would let a
    /// phone that has been in a loft all afternoon overwrite an edit made on
    /// another one an hour ago, purely because it spoke last.
    func sync() async {
        guard userID != nil else { return }
        guard network.isOnline else {
            // With no network, the synchronous cache is the best available
            // answer. An empty cache may now honestly become an empty state.
            hasCompletedInitialSync = true
            return
        }
        guard !isSyncing else {
            // Five edits in a row are one round trip and one more, not five.
            wantsAnotherPass = true
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            hasCompletedInitialSync = true
        }

        // A loop rather than a second call: `isSyncing` is still true until this
        // returns, so a pass that asked for itself again from inside would only
        // be turned away by its own guard.
        repeat {
            wantsAnotherPass = false
            await runPass()
        } while wantsAnotherPass
    }

    private func runPass() async {
        guard let userID else { return }
        guard let remote = try? await ScheduledVisitService.fetch() else { return }
        // A sign-out or an account switch while the fetch was in flight: that
        // list belongs to somebody else now.
        guard self.userID == userID else { return }

        let before = visits
        merge(remote)

        var cache = Cache(visits: visits,
                          unsynced: Array(unsynced),
                          tombstones: tombstones)
        prune(&cache)
        apply(cache)

        await push(userID: userID)
        save()

        if visits != before {
            // Reminders for visits booked on another phone, and none for the
            // ones that have already become quotes.
            await ScheduledVisitNotifications.rescheduleAll(
                visits: visits.filter { $0.recordedQuoteId == nil })
        }
    }

    /// Fold the server's list into ours. Last edit wins, per row.
    private func merge(_ remote: [ScheduledVisit]) {
        let deleted = Set(tombstones.map(\.id))
        var merged: [UUID: ScheduledVisit] = [:]
        for visit in visits { merged[visit.id] = visit }

        for row in remote {
            // Cancelled here and not yet there. The delete is still owed.
            if deleted.contains(row.id) { continue }

            guard let local = merged[row.id] else {
                // Booked on another device.
                merged[row.id] = row
                continue
            }
            if row.updatedAt > local.updatedAt {
                merged[row.id] = row
                // Their version won, so ours is no longer owed.
                unsynced.remove(row.id)
            }
        }

        let remoteIDs = Set(remote.map(\.id))
        for visit in visits where !remoteIDs.contains(visit.id) {
            // Not on the server and not waiting to be sent means it was deleted
            // on another device.
            if !unsynced.contains(visit.id) {
                merged[visit.id] = nil
            }
        }

        visits = merged.values.sorted { $0.date < $1.date }
    }

    /// Send what the server still doesn't know. Anything that fails keeps its
    /// flag and is tried again on the next pass.
    ///
    /// Every flag is cleared only after checking the account hasn't changed
    /// underneath: a sign-out or a swap mid-push means these results belong to
    /// a session that is over, and the rows are somebody else's problem now.
    private func push(userID: UUID) async {
        let owed = visits.filter { unsynced.contains($0.id) }
        if !owed.isEmpty,
           (try? await ScheduledVisitService.upsert(owed, userID: userID)) != nil,
           self.userID == userID {
            // Only forget a row that hasn't been edited again while the push was
            // in flight. Clearing the flag on one that has would drop the newer
            // edit outright — it was never sent, and nothing would send it.
            for visit in owed {
                guard let current = visits.first(where: { $0.id == visit.id }),
                      current.updatedAt == visit.updatedAt else { continue }
                unsynced.remove(visit.id)
            }
        }
        guard self.userID == userID else { return }
        // Ids we hold that are no longer on any visit — a row marked unsynced
        // and then deleted before it was ever sent.
        unsynced.formIntersection(Set(visits.map(\.id)))

        if !tombstones.isEmpty {
            let ids = tombstones.map(\.id)
            if (try? await ScheduledVisitService.delete(ids: ids)) != nil,
               self.userID == userID {
                tombstones.removeAll { tombstone in ids.contains(tombstone.id) }
            }
        }
    }

    // MARK: - Pruning

    /// Drop what the list is finished with: a visit that became a quote, once
    /// its day has been and gone, and a missed one the user has already been
    /// asked about.
    ///
    /// These become tombstones rather than quiet local removals. The row is on
    /// the server now, and a prune that only happened here would be undone by
    /// the very next pull.
    private func prune(_ cache: inout Cache) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var kept: [ScheduledVisit] = []
        for visit in cache.visits {
            let isFinished = visit.recordedQuoteId != nil
                ? calendar.startOfDay(for: visit.date) < today
                : visit.didPromptForMissedVisit
            if isFinished {
                if !cache.tombstones.contains(where: { $0.id == visit.id }) {
                    cache.tombstones.append(Tombstone(id: visit.id, deletedAt: .now))
                }
                cache.unsynced.removeAll { $0 == visit.id }
            } else {
                kept.append(visit)
            }
        }
        cache.visits = kept.sorted { $0.date < $1.date }
    }

    // MARK: - Storage

    private func apply(_ cache: Cache) {
        visits = cache.visits.sorted { $0.date < $1.date }
        unsynced = Set(cache.unsynced)
        tombstones = cache.tombstones
    }

    private func save() {
        guard let userID else { return }
        write(Cache(visits: visits,
                    unsynced: Array(unsynced),
                    tombstones: tombstones),
              userID: userID)
    }

    private func write(_ cache: Cache, userID: UUID) {
        guard let data = try? Self.encoder.encode(cache) else { return }
        LocalCache.save(data, for: .scheduledVisits, userID: userID)
    }

    private func loadCache(userID: UUID) -> Cache? {
        guard let data = LocalCache.loadData(for: .scheduledVisits, userID: userID) else {
            return nil
        }
        return try? Self.decoder.decode(Cache.self, from: data)
    }

    // MARK: - The old key

    private static let legacyKey = "scheduledVisits"
    private static let legacyOwnerKey = "scheduledVisitsLegacyOwnerID"

    /// A legacy cache has no account id in its shape. Claim it as soon as a
    /// known account has a scoped cache, even though there is nothing to
    /// migrate for that account, to stop a later account from inheriting it.
    private func claimLegacyVisits(for userID: UUID) {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: Self.legacyKey) != nil,
              defaults.string(forKey: Self.legacyOwnerKey) == nil
        else { return }
        defaults.set(userID.uuidString, forKey: Self.legacyOwnerKey)
    }

    /// Visits from before there was a table, taken into the account signing in.
    ///
    /// Safe to hand them to whoever that is: sign-out used to delete this key
    /// outright, so anything still in it belongs to the account still signed in.
    /// They go up as unsynced and stamped now — the server has never heard of
    /// them, so this device's copy is the only one there has ever been.
    ///
    /// Without this the change would lose the booked week of every user who has
    /// one right now, which is the bug it exists to fix.
    private func adoptLegacyVisits(for userID: UUID) -> Cache {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.legacyKey),
              let stored = try? JSONDecoder().decode([ScheduledVisit].self, from: data)
        else { return Cache() }

        // The shared key is a one-time migration only. It is never safe to
        // guess that it belongs to a different account that happens to sign
        // in on this device later.
        if let owner = defaults.string(forKey: Self.legacyOwnerKey),
           owner != userID.uuidString {
            return Cache()
        }
        defaults.set(userID.uuidString, forKey: Self.legacyOwnerKey)
        defaults.removeObject(forKey: Self.legacyKey)

        let adopted = stored.map { visit -> ScheduledVisit in
            var copy = visit
            copy.updatedAt = .now
            return copy
        }
        return Cache(visits: adopted, unsynced: adopted.map(\.id))
    }
}
