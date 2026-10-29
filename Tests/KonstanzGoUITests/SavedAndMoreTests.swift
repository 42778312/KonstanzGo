import XCTest

/// Favoriten, Zuletzt, Mehr and its pages, and links from widgets (plan T7: favourites edit, history delete).
final class SavedAndMoreTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["In deiner Nähe"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.buttons["Abfahrten"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSavedStopShowsInFavourites() {
        openStop("Sternenplatz")
        let star = app.buttons["Favorit"].firstMatch
        let wasSaved = star.isSelected
        if !wasSaved { star.tap() }
        app.buttons["Zurück"].firstMatch.tap()
        app.buttons["Abbrechen"].firstMatch.tap()
        app.buttons["Favoriten"].firstMatch.tap()
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
        app.buttons["Zurück"].firstMatch.tap()
        app.buttons["Abbrechen"].firstMatch.tap()
        app.buttons["Favoriten"].firstMatch.tap()
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
        app.buttons["Mehr"].firstMatch.tap()
        let offline = app.buttons["offlineCard"]
        XCTAssertTrue(offline.waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelContains: "Fahrplan bis").exists, "offline status missing")
        offline.tap()
        XCTAssertTrue(app.staticTexts["Bereit ohne Netz"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(labelContains: "MB").exists)
        app.buttons["Mehr"].firstMatch.tap()
        element(labelContains: "Datenschutz").tap()
        XCTAssertTrue(app.staticTexts["Deine Daten bleiben bei dir"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(labelContains: "Nutzungsstatistik").exists, "the app collects nothing (plan 0.3)")
        app.buttons["clearHistory"].tap()
        app.buttons.matching(identifier: "Verlauf löschen").lastMatch.tap()
        XCTAssertTrue(app.buttons["Verlauf gelöscht"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRouteLinkWithoutHomeOpensSearch() {
        app.open(URL(string: "konstanzgo://route/work")!)
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5) ||
                      app.staticTexts["Verbindungen"].waitForExistence(timeout: 10))
    }
}

private extension XCUIElementQuery {
    /// The dialog's button comes after the one that opened it.
    var lastMatch: XCUIElement { element(boundBy: count - 1) }
}
