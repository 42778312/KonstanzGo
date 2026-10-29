import XCTest

/// Starting the app after onboarding: the map with "In deiner Nähe" from the real timetable, and the tabs.
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

    /// A departure row ("Linie 9 nach …") or, late at night, the "nothing runs" card.
    private func departuresOrNothing(_ app: XCUIApplication, line: String, nothing: String) -> Bool {
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", line)).firstMatch
        let empty = app.staticTexts[nothing]
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            if row.exists || empty.exists { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.25))
        }
        return false
    }

    @MainActor
    func testMapShowsNearbyDeparturesFromTheTimetable() {
        let app = launch(language: "de", locale: "de_DE")
        XCTAssertTrue(app.staticTexts["In deiner Nähe"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Wohin möchtest du?"].exists)
        XCTAssertTrue(app.staticTexts["Offline bereit"].exists)
        XCTAssertTrue(departuresOrNothing(app, line: "Linie ", nothing: "Heute fährt hier nichts mehr."))
    }

    @MainActor
    func testTabs() {
        let app = launch(language: "de", locale: "de_DE")
        XCTAssertTrue(app.staticTexts["In deiner Nähe"].waitForExistence(timeout: 10))
        app.buttons["Mehr"].firstMatch.tap()
        XCTAssertTrue(app.buttons["replayOnboarding"].waitForExistence(timeout: 3))
        app.buttons["Favoriten"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["SCHNELL LOS"].waitForExistence(timeout: 3) ||
                      app.staticTexts["Schnell los"].exists)
        app.buttons["Karte"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["In deiner Nähe"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEnglish() {
        let app = launch(language: "en", locale: "en_GB")
        XCTAssertTrue(app.staticTexts["Near you"].waitForExistence(timeout: 10))
        XCTAssertTrue(departuresOrNothing(app, line: "Line ", nothing: "Nothing leaves here today any more."))
    }
}
