import XCTest

/// Starting the app after onboarding: the map with the search bar at the bottom (no nearby list, no tab bar), and Seeri's menu.
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
        // The weather replaced "Offline bereit": DWD's Konstanz station, or its last reading offline.
        let weather = app.descendants(matching: .any)["weather"]
        XCTAssertTrue(weather.waitForExistence(timeout: 15), "no weather in the corner")
        XCTAssertTrue(weather.label.hasPrefix("Wetter in Konstanz"), weather.label)
        XCTAssertFalse(app.staticTexts["In deiner Nähe"].exists, "the nearby list was removed")
    }

    @MainActor
    func testHandleOpensTheMenu() {
        let app = launch(language: "de", locale: "de_DE")
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Karte"].exists, "the tab bar was removed")
        app.buttons["moreHandle"].tap()
        XCTAssertTrue(app.buttons["replayOnboarding"].waitForExistence(timeout: 3))
        app.buttons["openFavorites"].tap()
        XCTAssertTrue(app.staticTexts["SCHNELL LOS"].waitForExistence(timeout: 3) ||
                      app.staticTexts["Schnell los"].exists)
        app.buttons["backLink"].firstMatch.tap()
        // A tap on the map closes the menu.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        // (The tap may land on a stop, which opens that stop instead of the bare map; either way the menu is gone.)
        XCTAssertTrue(app.buttons["replayOnboarding"].waitForNonExistence(timeout: 3), "the menu did not close")
    }

    @MainActor
    func testEnglish() {
        let app = launch(language: "en", locale: "en_GB")
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mapSearch"].label.contains("Where do you want to go?"), "got: \(app.buttons["mapSearch"].label)")
    }
}
