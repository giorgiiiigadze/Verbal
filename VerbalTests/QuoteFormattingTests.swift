import XCTest
@testable import Verbal

final class QuoteFormattingTests: XCTestCase {
    func testMoneyRoundingMatchesCurrencyExpectations() {
        XCTAssertEqual(12.345.roundedToCents, 12.35)
        XCTAssertEqual(12.344.roundedToCents, 12.34)
    }

    func testQuantityLabelKeepsWholeAndFractionalValuesReadable() {
        XCTAssertEqual(quantityLabel(8, "each"), "8 each")
        XCTAssertEqual(quantityLabel(2.5, "hours"), "2.50 hours")
        XCTAssertNil(quantityLabel(nil, "hours"))
    }

    func testRelativeDateLabelsAtBoundaries() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(quoteRelativeLabel(now.addingTimeInterval(-59), now: now), "now")
        XCTAssertEqual(quoteRelativeLabel(now.addingTimeInterval(-60), now: now), "1m ago")
        XCTAssertEqual(quoteRelativeLabel(now.addingTimeInterval(-3_600), now: now), "1h ago")
        XCTAssertEqual(quoteRelativeLabel(now.addingTimeInterval(-86_400), now: now), "1d ago")
    }

    func testTrimmingMakesWhitespaceOnlyInputAbsent() {
        XCTAssertNil(" \n\t ".trimmedOrNil)
        XCTAssertEqual("  Client name  ".trimmedOrNil, "Client name")
    }
}
