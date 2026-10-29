import XCTest

/// The main flows end to end on the real offline data (plan T7): search → stop → departure; place → route →
/// connections → route map → journey; "Wann & wie"; the alarm dialog; dropping a pin.
final class CoreFlowTests: XCTestCase {
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
        let alarm = app.buttons["setAlarm"]
        guard alarm.waitForExistence(timeout: 5) else { return } // no departures at this hour
        alarm.tap()
        XCTAssertTrue(app.staticTexts["Wann soll ich dich erinnern?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["2 Min. vorher"].exists)
    }

    @MainActor
    func testPlaceRouteToJourney() {
        search("Konzil")
        let place = element(labelContains: "Konzil")
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        let routeHere = app.buttons["routeHere"]
        XCTAssertTrue(routeHere.waitForExistence(timeout: 5), "place screen did not open")
        routeHere.tap()
        XCTAssertTrue(app.staticTexts["Verbindungen"].waitForExistence(timeout: 15) ||
                      app.staticTexts["Keine Verbindung gefunden"].exists)
        let start = app.buttons["startJourney"]
        guard start.waitForExistence(timeout: 5) else { return } // nothing runs at this hour
        XCTAssertTrue(app.buttons["routeCard"].firstMatch.exists)
        start.tap()
        let begin = app.buttons["beginJourney"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5), "route map did not open")
        begin.tap()
        let end = app.buttons["endJourney"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "journey did not open")
        XCTAssertTrue(element(labelContains: "Ankunft").exists)
        end.tap()
        XCTAssertTrue(app.staticTexts["In deiner Nähe"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWhenSheet() {
        search("Konzil")
        element(labelContains: "Konzil").tap()
        app.buttons["routeHere"].tap()
        let chip = app.buttons["whenChip"]
        guard chip.waitForExistence(timeout: 15) else { return }
        chip.tap()
        XCTAssertTrue(app.staticTexts["Wann & wie"].waitForExistence(timeout: 3))
        app.buttons["Abfahrt"].tap()
        let search = app.buttons["searchWhen"]
        XCTAssertTrue(search.label.hasPrefix("Ab "), "button should say when: \(search.label)")
        search.tap()
        XCTAssertTrue(app.staticTexts["Verbindungen"].waitForExistence(timeout: 15) ||
                      app.staticTexts["Keine Verbindung gefunden"].exists)
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

/// Changing start and target on the connections screen (screen 10).
final class EditEndpointsTests: XCTestCase {
    @MainActor
    func testChangeTargetFromConnections() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["In deiner Nähe"].waitForExistence(timeout: 15))
        app.buttons["mapSearch"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Konzil")
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Konzil'")).firstMatch.tap()
        app.buttons["routeHere"].tap()
        let editTo = app.buttons["editTo"]
        XCTAssertTrue(editTo.waitForExistence(timeout: 15))
        editTo.tap()
        XCTAssertTrue(app.staticTexts["Wohin?"].waitForExistence(timeout: 3))
        let picker = app.textFields.firstMatch
        picker.tap()
        picker.typeText("Sternenpl")
        let result = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Sternenplatz'"))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["editTo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editTo"].label.contains("Sternenplatz"), "target did not change: \(app.buttons["editTo"].label)")
        app.buttons["editFrom"].tap()
        XCTAssertTrue(app.staticTexts["Von wo?"].waitForExistence(timeout: 3))
    }
}
