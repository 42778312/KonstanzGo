import XCTest

/// Disruptions on the map, with a fixed closure (`-KGLiveSample`) instead of whatever the operator says today.
final class LiveNoticesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES",
                                "-KGLiveSample"]
        app.launch()
    }

    @MainActor
    func testSeeriTellsAboutAClosureAndTheListSuggestsStops() {
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        // Seeri says which stops; a tap on the message opens the list.
        let bubble = app.buttons["seeriNotice"]
        XCTAssertTrue(bubble.waitForExistence(timeout: 8), "Seeri didn't speak up")
        XCTAssertTrue(bubble.label.contains("Schulthaißstraße"), bubble.label)
        bubble.tap()
        XCTAssertTrue(app.buttons["closeNotices"].waitForExistence(timeout: 5), "the list didn't open")
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Wasserrohrbruch'")).firstMatch
        XCTAssertTrue(text.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Stand:'")).firstMatch.exists)
        // The operator's alternative opens with its departures.
        let alternative = app.buttons.matching(identifier: "alternativeStop").matching(NSPredicate(format: "label CONTAINS 'Döbelestraße'")).firstMatch
        XCTAssertTrue(alternative.exists)
        alternative.tap()
        XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 5), "the alternative didn't open")
        XCTAssertTrue(app.staticTexts["Döbelestraße"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["closureBanner"].exists, "the alternative isn't closed")
        app.buttons["closeStation"].tap()
        // It stays reachable after Seeri has spoken, and isn't announced twice.
        let pill = app.buttons["noticesPill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertFalse(bubble.waitForExistence(timeout: 3), "announced twice")
        pill.tap()
        XCTAssertTrue(app.buttons["closeNotices"].waitForExistence(timeout: 5))
    }
}
