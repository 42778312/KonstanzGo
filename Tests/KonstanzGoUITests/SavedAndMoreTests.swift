import XCTest

/// Favoriten, Zuletzt, Mehr and its pages, and links from widgets (plan T7: favourites edit, history delete).
final class SavedAndMoreTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 15))
    }

    private func element(labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openStop(_ name: String) {
        app.buttons["mapSearch"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        let result = element(labelContains: name)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        // A stop picked in the search opens as the target, with the connections and its star.
        XCTAssertTrue(app.buttons["closePlace"].waitForExistence(timeout: 5))
    }

    /// Closes the stop's sheet to get back to the map.
    private func closeStop() {
        app.buttons["closePlace"].tap()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavedStopShowsInFavourites() {
        openStop("Sternenplatz")
        let star = app.buttons["Favorit"].firstMatch
        let wasSaved = star.isSelected
        if !wasSaved { star.tap() }
        closeStop()
        // The search lists it under "Gemerkte Haltestellen".
        app.buttons["mapSearch"].firstMatch.tap()
        let stopsChip = app.buttons["category-1"]
        XCTAssertTrue(stopsChip.waitForExistence(timeout: 5))
        stopsChip.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sternenplatz'")).firstMatch
            .waitForExistence(timeout: 3), "saved stop missing from the search's categories")
        app.buttons["closeSearch"].tap()
        app.buttons["seeriMenu"].tap()
        XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 3))
        app.buttons["openFavorites"].tap()
        XCTAssertTrue(app.buttons["favoriteStop"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelContains: "Sternenplatz").exists)
        // Leave the store as it was.
        if !wasSaved {
            app.buttons["favoriteStop"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Favorit"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["Favorit"].firstMatch.tap()
        }
    }

    @MainActor
    func testRecentSearchesAndDeleteAll() {
        openStop("Bahnhof")
        closeStop()
        app.buttons["seeriMenu"].tap()
        XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 3))
        app.buttons["openFavorites"].tap()
        let link = app.buttons["recentLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(element(labelContains: "Bahnhof").waitForExistence(timeout: 5))
        app.buttons["clearRecent"].tap()
        app.buttons.matching(identifier: "Alle löschen").lastMatch.tap()
        XCTAssertTrue(app.staticTexts["Noch nichts gesucht"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMoreOfflineAndPrivacy() {
        app.buttons["seeriMenu"].tap()
        let offline = app.buttons["offlineCard"]
        XCTAssertTrue(offline.waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelContains: "Fahrplan bis").exists, "offline status missing")
        offline.tap()
        XCTAssertTrue(app.staticTexts["Bereit ohne Netz"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelContains: "MB").exists)
        app.buttons["backLink"].firstMatch.tap()
        element(labelContains: "Datenschutz").tap()
        XCTAssertTrue(app.staticTexts["Deine Daten bleiben bei dir"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(labelContains: "Nutzungsstatistik").exists, "the app collects nothing (plan 0.3)")
        let clear = app.buttons["clearHistory"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        if clear.isHittable { clear.tap() } else { clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        // The dialog's button, not the page's own (same title, identifier "clearHistory").
        app.buttons.matching(NSPredicate(format: "label == 'Verlauf löschen' AND identifier != 'clearHistory'"))
            .firstMatch.tap()
        XCTAssertTrue(app.buttons["Verlauf gelöscht"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRouteLinkWithoutHomeOpensSearch() {
        app.open(URL(string: "konstanzgo://route/work")!)
        // iOS may ask before opening a link in an app.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Open", "Öffnen"] where springboard.buttons[title].waitForExistence(timeout: 2) {
            springboard.buttons[title].tap()
        }
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5) ||
                      app.staticTexts["Verbindungen"].waitForExistence(timeout: 10))
    }
}

private extension XCUIElementQuery {
    /// The dialog's button comes after the one that opened it.
    var lastMatch: XCUIElement { element(boundBy: count - 1) }
}
