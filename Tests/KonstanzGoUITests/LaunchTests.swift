import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppStartsAndLoadsTheTimetable() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        XCTAssertTrue(app.staticTexts["appTitle"].waitForExistence(timeout: 5))
        let status = app.staticTexts["timetableStatus"]
        XCTAssertTrue(status.exists)
        XCTAssertTrue(status.label.hasPrefix("Fahrplan bis"), "data did not load: \(status.label)")
    }

    @MainActor
    func testEnglish() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()

        let status = app.staticTexts["timetableStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Timetable until"), "got: \(status.label)")
    }
}
