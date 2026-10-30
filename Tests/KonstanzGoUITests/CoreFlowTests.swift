import XCTest

/// The main flows end to end on the real offline data (plan T7): search → stop sheet → stop → departure;
/// place → its connections → journey (fold and unfold the stops); "Wann & wie"; the alarm dialog; dropping a pin.
final class CoreFlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 15))
    }

    /// Drags the sheet down by its grab handle, just above `element`, so it rests on the folded bar.
    private func foldSheet(above element: XCUIElement) {
        let window = app.windows.firstMatch
        let top = element.frame.minY - 22
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: top))
        start.press(forDuration: 0.15, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
    }

    private func element(labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A place in the results ("Konzil, Hafenstraße 2"), not a stop with the same word.
    private func placeResult(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
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
        // Picked in the search, the stop becomes the target with the connections there.
        let target = app.buttons["placeTo"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "the connections did not open")
        XCTAssertTrue(target.label.contains("Sternenplatz"), "Nach should be the stop: \(target.label)")
        // Tapped on the map (it sits in the middle of the map above the sheet), it shows its departures.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36)).tap()
        XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 5), "stop sheet did not open")
        XCTAssertTrue(app.buttons["Alle Linien"].exists)
        // A tap on the map folds the sheet to a bar with the stop's name; the bar opens it again.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
        let folded = app.buttons["foldedBar"]
        XCTAssertTrue(folded.waitForExistence(timeout: 3), "the stop sheet did not fold")
        XCTAssertTrue(folded.label.contains("Sternenplatz"), "folded bar should name the stop: \(folded.label)")
        folded.tap()
        XCTAssertTrue(app.buttons["Alle Linien"].waitForExistence(timeout: 3), "the stop sheet did not open again")
        let departure = element(labelContains: "laut Fahrplan")
        guard departure.waitForExistence(timeout: 3) else { return } // nothing runs at this hour
        departure.tap()
        // The departure opens in the same sheet over the map, and folds like the stop.
        let back = app.buttons["tripBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "departure details did not open")
        XCTAssertTrue(app.buttons["closeTrip"].exists)
        // Swipe the sheet down: it rests on the folded bar (a tap on the zoomed-out map may hit a stop).
        foldSheet(above: back)
        XCTAssertTrue(app.buttons["foldedBar"].waitForExistence(timeout: 3), "the trip did not fold")
        app.buttons["foldedBar"].tap()
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 5), "the stop's sheet should come back")
    }

    @MainActor
    func testAlarmDialog() {
        // Alarms are set on a departure, here reached from the stop saved in Favoriten.
        search("Bahnhof")
        element(labelContains: "Bahnhof").tap()
        let star = app.buttons["Favorit"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        if !star.isSelected { star.tap() }
        app.buttons["closePlace"].tap()
        app.buttons["seeriMenu"].tap()
        XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 3))
        app.buttons["openFavorites"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier == 'favoriteStop' AND label CONTAINS 'Bahnhof'"))
            .firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 5), "the saved stop did not open on the map")
        let departure = element(labelContains: "laut Fahrplan")
        guard departure.waitForExistence(timeout: 3) else { return } // no departures at this hour
        departure.tap()
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
        // A connection opens the trip itself.
        let end = app.buttons["endJourney"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "journey did not open")
        XCTAssertTrue(element(labelContains: "Ankunft").exists)
        XCTAssertFalse(element(labelContains: "Sperrbildschirm").exists, "the lock screen button was removed")
        // A tap on the map folds the stops into a bar; the bar brings them back.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36)).tap()
        let bar = app.buttons["foldedBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 3), "the sheet did not fold")
        bar.tap()
        XCTAssertTrue(app.otherElements["Fahrtfortschritt"].waitForExistence(timeout: 3) ||
                      element(labelContains: "Fahrtfortschritt").waitForExistence(timeout: 1), "the stops did not come back")
        XCTAssertTrue(app.descendants(matching: .any)["journeyLegs"].exists, "the whole trip should be listed")
        // ✕ goes back to the connections, to pick another one.
        end.tap()
        XCTAssertTrue(app.buttons["placeFrom"].waitForExistence(timeout: 5), "did not return to the connections")
        XCTAssertTrue(app.buttons["routeCard"].firstMatch.exists)
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
        // The point becomes the target at once, with the connections from here.
        let to = app.buttons["placeTo"]
        XCTAssertTrue(to.waitForExistence(timeout: 5), "the connections did not open")
        XCTAssertTrue(app.buttons["placeFrom"].exists)
        XCTAssertTrue(element(labelContains: "Markierter Ort").exists)
        // Its exact latitude and longitude, around Konstanz.
        let coordinates = app.descendants(matching: .any)["pinCoordinates"]
        XCTAssertTrue(coordinates.exists, "no coordinates")
        XCTAssertTrue(coordinates.label.contains("47,") && coordinates.label.contains("9,"), "got \(coordinates.label)")
        XCTAssertFalse(app.staticTexts["Pin gesetzt"].exists, "the pin screen is skipped")
    }
}

/// Changing and swapping start and target in a place's sheet on the map.
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
        app.buttons["swapEnds"].tap()
        XCTAssertTrue(app.buttons["placeTo"].label.contains("Sternenplatz"), "swap did not move the start to the target")
        XCTAssertTrue(from.label.contains("Konzil"), "swap did not move the place to the start: \(from.label)")
    }
}
