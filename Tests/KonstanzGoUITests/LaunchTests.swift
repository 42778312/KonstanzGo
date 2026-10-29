import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Skips onboarding (already finished) so the home screen shows after the short start.
    private func launch(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                                "-onboarding.finished", "YES"]
        app.launch()
        return app
    }

    @MainActor
    func testAppStartsAndLoadsTheTimetable() {
        let app = launch(language: "de", locale: "de_DE")
        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 5))
        let status = app.staticTexts["timetableStatus"]
        XCTAssertTrue(status.exists)
        XCTAssertTrue(status.label.hasPrefix("Fahrplan bis"), "data did not load: \(status.label)")
    }

    @MainActor
    func testEnglish() {
        let app = launch(language: "en", locale: "en_GB")
        let status = app.staticTexts["timetableStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Timetable until"), "got: \(status.label)")
    }
}
