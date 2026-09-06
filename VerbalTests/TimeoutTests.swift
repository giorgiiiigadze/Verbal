import XCTest
@testable import Verbal

/// `withTimeout` sits on the one path the user actively waits on — the
/// transcript going out for extraction — so its two endings are worth pinning
/// down. The third case is the one that would go unnoticed in use: a timeout
/// that fires but leaves the work running still costs the OpenAI call it was
/// meant to abandon.
final class TimeoutTests: XCTestCase {
    func testFastWorkReturnsItsValue() async throws {
        let result = try await withTimeout(.seconds(5)) { "quote" }
        XCTAssertEqual(result, "quote")
    }

    func testSlowWorkTimesOut() async {
        do {
            _ = try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(30))
                return "never"
            }
            XCTFail("Expected the deadline to be enforced")
        } catch {
            XCTAssertTrue(error is TimedOutError)
        }
    }

    /// The point of racing rather than merely giving up on the wait: the losing
    /// task must actually be cancelled, or a timed-out extraction goes on being
    /// billed while nothing is left to receive it.
    func testTimeoutCancelsTheWorkItAbandons() async {
        let observed = Cancellation()
        do {
            _ = try await withTimeout(.milliseconds(50)) {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    await observed.record()
                }
                return "never"
            }
            XCTFail("Expected the deadline to be enforced")
        } catch {
            XCTAssertTrue(error is TimedOutError)
        }

        // The cancellation lands after the throw, so give it a moment to arrive
        // rather than racing the assertion against it.
        for _ in 0..<50 where await !observed.wasCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let wasCancelled = await observed.wasCancelled
        XCTAssertTrue(wasCancelled, "The abandoned work kept running")
    }

    /// An error the operation raises itself must reach the caller unchanged —
    /// a real extraction failure must not arrive looking like a timeout.
    func testOperationErrorIsNotDisguisedAsATimeout() async {
        struct Boom: Error {}
        do {
            _ = try await withTimeout(.seconds(5)) { throw Boom() }
            XCTFail("Expected the operation's own error")
        } catch {
            XCTAssertTrue(error is Boom)
            XCTAssertFalse(error is TimedOutError)
        }
    }
}

private actor Cancellation {
    private(set) var wasCancelled = false
    func record() { wasCancelled = true }
}
