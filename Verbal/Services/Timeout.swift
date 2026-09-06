//
//  Timeout.swift
//  Verbal
//
//  A deadline for work the user is watching.
//
//  `URLSession`'s own default gives up after 60 seconds. That is a fine floor
//  for a background sync and far too long for the one screen where somebody has
//  finished speaking and is waiting to see their quote: extraction returns in
//  about nine seconds and has never taken more than twenty-four, so a minute of
//  spinner is not patience, it is a hang the app has decided to sit through.
//
//  Racing rather than configuring the session, because the timeout that matters
//  is per-call. The same client uploads logos and syncs visits, and neither
//  wants a deadline this short.
//

import Foundation

/// Thrown when `withTimeout` gives up. Carries no message of its own — callers
/// map it to something that fits the screen it happened on.
struct TimedOutError: Error {}

/// Run `operation`, giving up after `duration`.
///
/// The losing task is cancelled, and `URLSession` honours that by tearing the
/// connection down — so a timeout here stops the request rather than merely
/// stopping the wait for it.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimedOutError()
        }
        // The first to finish decides it, win or lose. Cancelling the rest
        // before returning is what stops the sleeper outliving the call.
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimedOutError() }
        return result
    }
}
