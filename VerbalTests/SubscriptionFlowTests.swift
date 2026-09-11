import XCTest
@testable import Verbal

@MainActor
final class SubscriptionFlowTests: XCTestCase {
    func testRestoreReportsActiveSubscriptionAsRestored() {
        XCTAssertEqual(SubscriptionFlow.restoreOutcome(isPro: true), .restored)
    }

    func testRestoreWithoutEntitlementDoesNotClaimSuccess() {
        XCTAssertEqual(SubscriptionFlow.restoreOutcome(isPro: false), .noActiveSubscription)
    }

    func testSubscriberQuotaRefusalRetriesAfterEntitlementSync() {
        XCTAssertEqual(
            SubscriptionFlow.quotaRefusalOutcome(isPro: true),
            .retryAfterEntitlementSync
        )
    }

    func testFreeUserQuotaRefusalShowsPaywall() {
        XCTAssertEqual(
            SubscriptionFlow.quotaRefusalOutcome(isPro: false),
            .showPaywall
        )
    }

    func testThirdDailyQuoteShowsPaywallBeforeRecorderOpens() {
        XCTAssertEqual(
            SubscriptionFlow.recordRequestOutcome(serverIsPro: false, remaining: 0),
            .showPaywall
        )
    }

    func testFreeUserWithAllowanceCanOpenRecorder() {
        XCTAssertEqual(
            SubscriptionFlow.recordRequestOutcome(serverIsPro: false, remaining: 1),
            .openRecorder
        )
    }

    func testVerifiedSubscriberCanOpenRecorderAfterFreeAllowanceIsUsed() {
        XCTAssertEqual(
            SubscriptionFlow.recordRequestOutcome(serverIsPro: true, remaining: 0),
            .openRecorder
        )
    }

    func testPendingPurchaseExplainsWhatWillHappen() {
        XCTAssertEqual(
            StoreError.purchasePending.errorDescription,
            "Your purchase is waiting for approval. We'll unlock Pro when Apple confirms it."
        )
    }
}
