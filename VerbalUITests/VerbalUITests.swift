import XCTest

final class VerbalUITests: XCTestCase {
    @MainActor
    func testLaunchShowsAnAccessibleSignInAction() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.buttons["Continue with Google"].waitForExistence(timeout: 8),
            "The launch screen should always provide a reachable sign-in action."
        )
    }
}
