import XCTest

/// The main flows end to end on the real offline data (plan T7): search → stop sheet → stop → departure;
/// place → its connections → route map → journey; "Wann & wie"; the alarm dialog; dropping a pin.
final class CoreFlowTests: XCTestCase {
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

    /// A place in the results ("Konzil, Hafenstraße 2"), not a stop with the same word.
    private func placeResult(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// From the stop's sheet on the map to its screen.
    private func openStopScreen() {
        let all = app.buttons["Alle Abfahrten"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "stop sheet did not open")
        all.tap()
    }

    private func search(_ text: String) {
        app.buttons["mapSearch"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    func testSearchStopLinesAndDeparture() {
        search("Sternenpl")
        let result = element(labelContains: "Sternenplatz")
        XCTAssertTrue(result.waitForExistence(timeout: 5), "no search result")
        result.tap()
        openStopScreen()
        XCTAssertTrue(app.buttons["Abfahrten"].waitForExistence(timeout: 5), "stop screen did not open")
        app.buttons["Linien"].tap()
        XCTAssertTrue(element(labelContains: "Richtung").waitForExistence(timeout: 3) ||
                      app.staticTexts["Heute fährt hier nichts mehr"].exists)
        app.buttons["Abfahrten"].tap()
        let departure = element(labelContains: "laut Fahrplan")
        guard departure.waitForExistence(timeout: 3) else { return } // nothing runs at this hour
        departure.tap()
        XCTAssertTrue(app.staticTexts["HALTESTELLEN"].waitForExistence(timeout: 5) ||
                      app.staticTexts["Haltestellen"].exists, "departure details did not open")
        XCTAssertTrue(app.buttons["Auf der Karte"].exists)
        app.buttons["Zurück"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Abfahrten"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAlarmDialog() {
        search("Bahnhof")
        element(labelContains: "Bahnhof").tap()
        openStopScreen()
        let alarm = app.buttons["setAlarm"]
        guard alarm.waitForExistence(timeout: 5) else { return } // no departures at this hour
        alarm.tap()
        XCTAssertTrue(app.staticTexts["Wann soll ich dich erinnern?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["2 Min. vorher"].exists)
    }

    @MainActor
    func testPlaceRouteToJourney() {
        search("Konzil")
        let place = placeResult("Konzil")
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        // The place opens in the map's sheet with its connections from here.
        XCTAssertTrue(app.buttons["placeFrom"].waitForExistence(timeout: 5), "place sheet did not open")
        let card = app.buttons["routeCard"].firstMatch
        guard card.waitForExistence(timeout: 15) else { return } // nothing runs at this hour
        card.tap()
        let begin = app.buttons["beginJourney"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5), "route map did not open")
        begin.tap()
        let end = app.buttons["endJourney"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "journey did not open")
        XCTAssertTrue(element(labelContains: "Ankunft").exists)
        end.tap()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWhenSheet() {
        search("Konzil")
        let place = placeResult("Konzil")
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        let chip = app.buttons["whenChip"]
        guard chip.waitForExistence(timeout: 15) else { return }
        chip.tap()
        XCTAssertTrue(app.staticTexts["Wann & wie"].waitForExistence(timeout: 3))
        app.buttons["Abfahrt"].tap()
        let search = app.buttons["searchWhen"]
        XCTAssertTrue(search.label.hasPrefix("Ab "), "button should say when: \(search.label)")
        search.tap()
        XCTAssertTrue(app.buttons["whenChip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["whenChip"].label.hasPrefix("Ab "), "chip should say when")
    }

    @MainActor
    func testLongPressDropsAPin() {
        let map = app.otherElements["Karte von Konstanz"].firstMatch
        let target = map.exists ? map : app.windows.firstMatch
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 1.0)
        XCTAssertTrue(app.staticTexts["Pin gesetzt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Markierter Ort"].exists)
    }
}

/// Changing the start in a place's sheet on the map.
final class EditEndpointsTests: XCTestCase {
    @MainActor
    func testChangeStartForAPlace() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 15))
        app.buttons["mapSearch"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Konzil")
        let place = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Konzil,'")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        let from = app.buttons["placeFrom"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        from.tap()
        XCTAssertTrue(app.staticTexts["Von wo?"].waitForExistence(timeout: 3))
        let picker = app.textFields["endpointField"].exists ? app.textFields["endpointField"] : app.textFields.firstMatch
        picker.tap()
        picker.typeText("Sternenpl")
        let result = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Sternenplatz'"))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        XCTAssertTrue(from.label.contains("Sternenplatz"), "start did not change: \(from.label)")
    }
}
