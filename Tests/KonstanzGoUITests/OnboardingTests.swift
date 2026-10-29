import XCTest

/// Walks through onboarding (plan S3.8): once allowing both permissions, once refusing both.
final class OnboardingTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(permissions: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                                "-KGResetOnboarding", "YES", "-KGPermissions", permissions]
        app.launch()
        return app
    }

    @MainActor
    private func walkToPermissions(_ app: XCUIApplication) {
        // The start screen skips on tap.
        app.tap()
        let first = app.buttons["Los geht's"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let next = app.buttons["Weiter"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssertTrue(app.staticTexts["Sag mir, wohin du willst."].waitForExistence(timeout: 3))
        app.buttons["Weiter"].tap()
    }

    @MainActor
    func testAllowBoth() {
        let app = launch(permissions: "allow")
        walkToPermissions(app)
        let allow = app.buttons["allowPermissions"]
        XCTAssertTrue(allow.waitForExistence(timeout: 3))
        allow.tap()
        XCTAssertTrue(app.staticTexts["Alles bereit!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alarme an"].waitForExistence(timeout: 3))
        app.buttons["finishOnboarding"].tap()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRefuseBoth() {
        let app = launch(permissions: "deny")
        walkToPermissions(app)
        app.buttons["allowPermissions"].tap()
        XCTAssertTrue(app.staticTexts["Alles bereit!"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alarme an"].exists)
        app.buttons["finishOnboarding"].tap()
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 5))
    }
}
