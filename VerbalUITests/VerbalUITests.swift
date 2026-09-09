import XCTest

final class VerbalUITests: XCTestCase {
    @MainActor
    func testLaunchShowsAnAccessiblePathToSignIn() throws {
        let app = XCUIApplication()
        app.launch()

        // A new device starts with onboarding, a returning signed-out person
        // starts at sign-in, and a simulator may retain a valid signed-in
        // session. Every state must expose its primary next action.
        if app.buttons["Get started"].waitForExistence(timeout: 8) { return }
        if app.buttons["Record a quote"].exists { return }

        XCTAssertTrue(
            app.buttons["Continue with Google"].waitForExistence(timeout: 8),
            "The launch screen should offer onboarding or a reachable sign-in action."
        )
    }
}
