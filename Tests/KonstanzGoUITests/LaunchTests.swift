import XCTest

/// Starting the app after onboarding: the map with the search bar at the bottom (no nearby list), and the tabs.
final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                                "-onboarding.finished", "YES"]
        app.launch()
        return app
    }

    @MainActor
    func testMapStartsWithWhereTo() {
        let app = launch(language: "de", locale: "de_DE")
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mapSearch"].label.contains("Wohin möchtest du?"))
        XCTAssertTrue(app.staticTexts["Offline bereit"].exists)
        XCTAssertFalse(app.staticTexts["In deiner Nähe"].exists, "the nearby list was removed")
    }

    @MainActor
    func testTabs() {
        let app = launch(language: "de", locale: "de_DE")
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        app.buttons["Mehr"].firstMatch.tap()
        XCTAssertTrue(app.buttons["replayOnboarding"].waitForExistence(timeout: 3))
        app.buttons["Favoriten"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["SCHNELL LOS"].waitForExistence(timeout: 3) ||
                      app.staticTexts["Schnell los"].exists)
        app.buttons["Karte"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEnglish() {
        let app = launch(language: "en", locale: "en_GB")
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mapSearch"].label.contains("Where do you want to go?"), "got: \(app.buttons["mapSearch"].label)")
    }
}
