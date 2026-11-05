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
        // Seeri on the map opens the list again; it isn't announced twice.
        XCTAssertFalse(bubble.waitForExistence(timeout: 3), "announced twice")
        let seeri = app.buttons["seeriMenu"]
        XCTAssertTrue(seeri.waitForExistence(timeout: 5))
        seeri.tap()
        // Seeri in the list closes it.
        let close = app.buttons["closeNotices"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3), "Seeri didn't close the list")
        // A tap on the map closes it too.
        XCTAssertTrue(seeri.waitForExistence(timeout: 3))
        seeri.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.08)).tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3), "a tap on the map didn't close the list")
    }

    /// The menu now rises out of the search bar: pull it up, or tap its handle.
    @MainActor
    func testPullingUpTheSearchBarOpensTheMenu() {
        let bar = app.buttons["mapSearch"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        let from = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -180)))
        XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 5), "the menu didn't rise")
    }
}
