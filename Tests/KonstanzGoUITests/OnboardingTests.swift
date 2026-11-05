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
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The start screen skips on tap; the film has a skip button.
    @MainActor
    private func walkToPermissions(_ app: XCUIApplication) {
        app.tap()
        let skip = app.buttons["introSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
    }

    /// The real app, one step per tap: nothing moves on by itself. A picture of each is kept to check by eye.
    @MainActor
    func testStepsShowTheAppAndWaitForATap() {
        let app = launch(permissions: "allow")
        app.tap()
        let next = app.buttons["introNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Hallo, ich bin Seeri"].waitForExistence(timeout: 3))
        for step in 1...6 {
            sleep(4)
            shot(app, "step-\(step)")
            if step == 1 { XCTAssertTrue(app.staticTexts["Hallo, ich bin Seeri"].exists, "moved on by itself") }
            if step == 3 { XCTAssertTrue(app.staticTexts["Sternenplatz"].exists, "the stop's real list is missing") }
            next.tap()
        }
        XCTAssertTrue(app.buttons["allowPermissions"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAllowBoth() {
        let app = launch(permissions: "allow")
        walkToPermissions(app)
        let allow = app.buttons["allowPermissions"]
        XCTAssertTrue(allow.waitForExistence(timeout: 3))
        allow.tap()
        XCTAssertTrue(app.staticTexts["Alles bereit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alarme an"].waitForExistence(timeout: 3))
        app.buttons["finishOnboarding"].tap()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testRefuseBoth() {
        let app = launch(permissions: "deny")
        walkToPermissions(app)
        app.buttons["allowPermissions"].tap()
        XCTAssertTrue(app.staticTexts["Alles bereit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alarme an"].exists)
        app.buttons["finishOnboarding"].tap()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
    }
}
