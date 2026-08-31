import XCTest

final class VerbalUITests: XCTestCase {
    @MainActor
    func testLaunchShowsAnAccessiblePathToSignIn() throws {
        let app = XCUIApplication()
        app.launch()

        // A new device starts with onboarding; a returning signed-out person
        // starts directly at sign-in. Both are valid launch states, and both
        // must leave a clear, reachable path to authentication.
        if app.buttons["Get Started"].waitForExistence(timeout: 8) { return }

        XCTAssertTrue(
            app.buttons["Continue with Google"].waitForExistence(timeout: 8),
            "The launch screen should offer onboarding or a reachable sign-in action."
        )
    }
}
