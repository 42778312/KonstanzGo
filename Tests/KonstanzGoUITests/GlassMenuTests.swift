import XCTest

/// The app's glass menus open from where they're asked for, and their choices work.
final class GlassMenuTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 15))
    }

    private func picture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAlarmDropdownChangesTheMinutes() {
        app.buttons["moreHandle"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Abfahrtsalarm'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        sleep(1)
        picture("more-before")
        row.tap()
        let five = app.buttons["5 Min. vorher"]
        XCTAssertTrue(five.waitForExistence(timeout: 3), "the dropdown did not open")
        sleep(1)
        picture("more-dropdown")
        five.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '5 Min. vorher'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["10 Min. vorher"].exists, "the dropdown stayed open")
    }

    @MainActor
    func testLongPressOnAResultOffersSaving() {
        app.buttons["mapSearch"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Bahnhof")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bahnhof'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.press(forDuration: 0.8)
        let save = app.buttons["Merken"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "the long press did not open the menu")
        XCTAssertTrue(field.exists, "the long press also opened the result")
        sleep(1)
        picture("search-menu")
    }

    /// Opens through a saved stop, as `CoreFlowTests` does; without departures at this hour it can't be checked.
    @MainActor
    func testAlarmMenuOverTheTripSheet() throws {
        app.buttons["mapSearch"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Bahnhof")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bahnhof'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let star = app.buttons["Favorit"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        if !star.isSelected { star.tap() }
        app.buttons["closePlace"].tap()
        app.buttons["moreHandle"].tap()
        XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 3))
        app.buttons["openFavorites"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier == 'favoriteStop' AND label CONTAINS 'Bahnhof'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 5))
        // Not the first bus: it may leave too soon for an alarm.
        let departures = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'laut Fahrplan' OR label CONTAINS 'Live'"))
        guard departures.firstMatch.waitForExistence(timeout: 5) else { throw XCTSkip("no departures at this hour") }
        departures.element(boundBy: min(departures.count - 1, 3)).tap()
        let alarm = app.buttons["setAlarm"]
        guard alarm.waitForExistence(timeout: 5) else { throw XCTSkip("the bus leaves too soon for an alarm") }
        alarm.tap()
        XCTAssertTrue(app.staticTexts["Wann soll ich dich erinnern?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["2 Min. vorher"].exists)
        sleep(1)
        picture("alarm-menu")
    }

    @MainActor
    func testClearHistoryMenuOnThePrivacyPage() {
        app.buttons["moreHandle"].tap()
        let privacy = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Datenschutz'")).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        let clear = app.buttons["clearHistory"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        if clear.isHittable { clear.tap() } else { clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        XCTAssertTrue(app.staticTexts["Suchverlauf und Fahrten löschen?"].waitForExistence(timeout: 3))
        sleep(1)
        picture("clear-menu")
    }
}
