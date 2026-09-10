import XCTest
@testable import Verbal

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testShortFlowIsFiveStepsInOrder() {
        XCTAssertEqual(
            OnboardingModel(usesShortFlow: true).steps,
            [.hook, .profile, .stat, .setup, .notifications]
        )
    }

    func testLongFlowRemainsAvailableInOriginalOrder() {
        XCTAssertEqual(
            OnboardingModel(usesShortFlow: false).steps,
            [.hook, .method, .quoteVolume, .quoteDuration, .stat, .trade,
             .prices, .business, .summary, .milestone, .goal, .commitment,
             .expectations, .notifications]
        )
    }

    func testShortProfileStartsWithCompleteEstimate() {
        let model = OnboardingModel(usesShortFlow: true)

        XCTAssertEqual(model.answers.method, .phoneAtNight)
        XCTAssertEqual(model.answers.quotesPerWeek, 4)
        XCTAssertEqual(model.answers.minutesPerQuote, 20)
        XCTAssertNotNil(model.answers.hoursSavedPerYear)
    }

    func testLongFlowKeepsQuestionsUnanswered() {
        let model = OnboardingModel(usesShortFlow: false)

        XCTAssertNil(model.answers.method)
        XCTAssertNil(model.answers.quotesPerWeek)
        XCTAssertNil(model.answers.minutesPerQuote)
    }

    func testSetupHourlyRateUsesBothExistingStoragePaths() {
        OnboardingDraft.clear()
        OnboardingAnswers.clear()
        defer {
            OnboardingDraft.clear()
            OnboardingAnswers.clear()
        }

        let model = OnboardingModel(usesShortFlow: true)
        model.hourlyRateText = "37,50"
        model.saveDraft()

        XCTAssertEqual(OnboardingAnswers.load().hourlyRate, 37.5)
        let savedRate = try? XCTUnwrap(OnboardingDraft.load()?.rates.first)
        XCTAssertEqual(savedRate?.name, OnboardingModel.hourlyRateName)
        XCTAssertEqual(savedRate?.unit, "hour")
        XCTAssertEqual(savedRate?.price, 37.5)
        XCTAssertEqual(savedRate?.type, TradePresets.type)
    }
}
