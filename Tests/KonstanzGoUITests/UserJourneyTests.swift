import XCTest

/// The release check from a user's side: a fresh install used the way a new rider in Konstanz would, step by
/// step, with a screenshot kept at each step. Then the same app in English, with very large text, and its
/// launch time. Runs on the real offline data; where nothing runs at the hour of the test, the bus steps say so
/// and go on.
final class UserJourneyTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    private func launch(fresh: Bool = false, language: String = "de", locale: String = "de_DE",
                        extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale] + extra
        app.launchArguments += fresh ? ["-KGFreshInstall", "YES", "-KGPermissions", "allow"]
                                     : ["-onboarding.finished", "YES"]
        app.launch()
    }

    /// Drags the sheet down by its grab handle, just above `element`, so it rests on the folded bar.
    private func foldSheet(above element: XCUIElement) {
        let window = app.windows.firstMatch
        let top = element.frame.minY - 22
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: top))
        start.press(forDuration: 0.15, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
    }

    private func element(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One thing the user does, then a screenshot of the result named after it.
    @MainActor
    private func step(_ name: String, _ body: () -> Void) {
        body()
        shot(name)
    }

    private func tapMap(_ x: Double, _ y: Double) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }

    private func search(_ text: String) {
        app.buttons["mapSearch"].firstMatch.tap()
        let field = app.textFields["searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "search did not open")
        field.tap()
        field.typeText(text)
    }

    private func pickPlace(_ name: String) {
        let place = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5), "\(name) not found")
        place.tap()
        XCTAssertTrue(app.buttons["placeTo"].waitForExistence(timeout: 5), "the connections did not open")
    }

    private func pickInPicker(_ text: String, _ name: String) {
        let field = app.textFields["endpointField"].exists ? app.textFields["endpointField"] : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(text)
        let result = element(name)
        XCTAssertTrue(result.waitForExistence(timeout: 5), "\(name) not offered")
        result.tap()
    }

    // MARK: A first day in Konstanz

    @MainActor
    func testFirstDayInKonstanz() {
        launch(fresh: true)

        step("01 Start und Willkommen") {
            app.tap()  // the start screen skips on tap
            let start = app.buttons["Los geht's"]
            XCTAssertTrue(start.waitForExistence(timeout: 8), "welcome did not show")
            XCTAssertTrue(element("Hallo, ich bin Seeri").exists)
        }
        step("02 Onboarding bis Alles bereit") {
            app.buttons["Los geht's"].tap()
            XCTAssertTrue(app.buttons["Weiter"].waitForExistence(timeout: 3))
            app.buttons["Weiter"].tap()
            XCTAssertTrue(app.buttons["Weiter"].waitForExistence(timeout: 3))
            app.buttons["Weiter"].tap()
            let allow = app.buttons["allowPermissions"]
            XCTAssertTrue(allow.waitForExistence(timeout: 3))
            allow.tap()
            XCTAssertTrue(app.staticTexts["Alles bereit"].waitForExistence(timeout: 5))
        }
        step("03 Seeris Tour startet von selbst") {
            app.buttons["finishOnboarding"].tap()
            let next = app.buttons["tourNext"]
            XCTAssertTrue(next.waitForExistence(timeout: 10), "the tour did not start after onboarding")
            XCTAssertTrue(app.buttons["tourSkip"].exists)
        }
        step("04 Tour bis zum Ende") {
            let next = app.buttons["tourNext"]
            for _ in 0..<12 where next.exists { next.tap() }
            XCTAssertTrue(next.waitForNonExistence(timeout: 3), "the tour did not end")
            XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["mapSearch"].isHittable, "map covered after the tour")
            XCTAssertTrue(app.descendants(matching: .any)["weather"].waitForExistence(timeout: 15), "no weather in the corner")
        }
        step("05 Suche nach einem Ort") {
            search("Konzil")
            pickPlace("Konzil")
            XCTAssertTrue(app.buttons["placeTo"].label.contains("Konzil"))
        }
        step("06 Start ändern und tauschen") {
            app.buttons["placeFrom"].tap()
            XCTAssertTrue(app.staticTexts["Von wo?"].waitForExistence(timeout: 3))
            pickInPicker("Universit", "Universität")
            XCTAssertTrue(app.buttons["placeFrom"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["placeFrom"].label.contains("Universität"))
            app.buttons["swapEnds"].tap()
            XCTAssertTrue(app.buttons["placeTo"].label.contains("Universität"), "swap failed")
            app.buttons["swapEnds"].tap()
            XCTAssertTrue(app.buttons["placeTo"].label.contains("Konzil"))
        }
        step("07 Abfahrtszeit wählen") {
            let when = app.buttons["whenChip"]
            XCTAssertTrue(when.waitForExistence(timeout: 5))
            when.tap()
            XCTAssertTrue(app.staticTexts["Wann & wie"].waitForExistence(timeout: 3))
            app.buttons["Abfahrt"].tap()
            app.buttons["searchWhen"].tap()
            XCTAssertTrue(app.buttons["whenChip"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["whenChip"].label.hasPrefix("Ab "), "time not taken: \(app.buttons["whenChip"].label)")
        }
        let card = app.buttons["routeCard"].firstMatch
        if card.waitForExistence(timeout: 15) {
            step("08 Fahrt öffnen: ganze Route") {
                card.tap()
                XCTAssertTrue(app.buttons["endJourney"].waitForExistence(timeout: 5), "the trip did not open")
                XCTAssertTrue(app.descendants(matching: .any)["journeyLegs"].exists)
                XCTAssertTrue(element("Ankunft").exists)
            }
            step("09 Karte antippen: Liste klappt zusammen") {
                tapMap(0.5, 0.25)
                XCTAssertTrue(app.buttons["foldedBar"].waitForExistence(timeout: 3), "the stops did not fold")
            }
            step("10 Liste wieder öffnen, zurück zu den Verbindungen") {
                app.buttons["foldedBar"].tap()
                XCTAssertTrue(app.descendants(matching: .any)["journeyLegs"].waitForExistence(timeout: 3))
                app.buttons["endJourney"].tap()
                XCTAssertTrue(app.buttons["placeFrom"].waitForExistence(timeout: 5), "✕ did not go back")
            }
        } else {
            shot("08–10 übersprungen: zu dieser Uhrzeit fährt nichts")
        }
        step("11 Ort merken und schließen") {
            let star = app.buttons["Favorit"].firstMatch
            XCTAssertTrue(star.waitForExistence(timeout: 3))
            if !star.isSelected { star.tap() }
            app.buttons["closePlace"].tap()
            XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 5))
        }
        step("12 Haltestelle suchen: Ziel wird gesetzt") {
            search("Sternenpl")
            let result = element("Sternenplatz")
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            result.tap()
            XCTAssertTrue(app.buttons["placeTo"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["placeTo"].label.contains("Sternenplatz"))
        }
        step("13 Haltestelle auf der Karte antippen: Abfahrten") {
            tapMap(0.5, 0.36)
            XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 5), "the stop's departures did not open")
            XCTAssertTrue(app.buttons["Alle Linien"].exists)
            XCTAssertFalse(app.buttons["Alle Abfahrten"].exists, "removed button is back")
        }
        step("14 Abfahrten ab einer anderen Zeit") {
            app.buttons["stationTime"].tap()
            XCTAssertTrue(app.staticTexts["Abfahrten ab"].waitForExistence(timeout: 3))
            app.buttons["Jetzt"].tap()
            XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 3))
        }
        let departure = element("laut Fahrplan")
        if departure.waitForExistence(timeout: 3) {
            step("15 Abfahrt öffnen: Haltestellen der Fahrt") {
                departure.tap()
                XCTAssertTrue(app.buttons["tripBack"].waitForExistence(timeout: 5))
                // Swipe the sheet down to fold it (a tap on the zoomed-out map may land on a stop).
                foldSheet(above: app.buttons["tripBack"])
                XCTAssertTrue(app.buttons["foldedBar"].waitForExistence(timeout: 3), "the trip did not fold")
                app.buttons["foldedBar"].tap()
                app.buttons["tripBack"].tap()
                XCTAssertTrue(app.buttons["closeStation"].waitForExistence(timeout: 5))
            }
        }
        step("16 Haltestelle schließen") {
            app.buttons["closeStation"].tap()
            XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 5))
        }
        step("17 Karte gedrückt halten: Ziel mit Koordinaten") {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.25)).press(forDuration: 1.0)
            XCTAssertTrue(app.buttons["placeTo"].waitForExistence(timeout: 5), "long press did not set a target")
            let coordinates = app.descendants(matching: .any)["pinCoordinates"]
            XCTAssertTrue(coordinates.exists)
            XCTAssertTrue(coordinates.label.contains("° N"), "got \(coordinates.label)")
            app.buttons["closePlace"].tap()
        }
        step("18 Kartenebenen: Busse aus und an") {
            app.buttons["Kartenebenen"].firstMatch.tap()
            let vehicles = app.switches["Busse & Züge"].firstMatch
            XCTAssertTrue(vehicles.waitForExistence(timeout: 3))
            vehicles.tap()
            vehicles.tap()
            app.buttons["Schließen"].firstMatch.tap()
        }
        step("19 Menü über Seeri, Favoriten") {
            app.buttons["moreHandle"].tap()
            XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 3))
            app.buttons["openFavorites"].tap()
            XCTAssertTrue(element("Konzil").waitForExistence(timeout: 5), "the saved place is missing")
            app.buttons["backLink"].firstMatch.tap()
        }
        step("20 Offline-Daten und Datenschutz") {
            let offline = app.buttons["offlineCard"]
            XCTAssertTrue(offline.waitForExistence(timeout: 3))
            offline.tap()
            XCTAssertTrue(app.staticTexts["Bereit ohne Netz"].waitForExistence(timeout: 5))
            app.buttons["backLink"].firstMatch.tap()
            element("Datenschutz").tap()
            XCTAssertTrue(app.staticTexts["Deine Daten bleiben bei dir"].waitForExistence(timeout: 5))
            app.buttons["backLink"].firstMatch.tap()
        }
        step("21 Tour noch einmal und überspringen") {
            let start = app.buttons["startTour"]
            if !start.isHittable { app.swipeUp() }
            start.tap()
            let skip = app.buttons["tourSkip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 5))
            skip.tap()
            XCTAssertTrue(skip.waitForNonExistence(timeout: 3))
        }
        step("22 Sprachsuche öffnen") {
            app.buttons["mapVoiceSearch"].tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for _ in 0..<2 {
                for title in ["Allow", "Erlauben", "OK"] where springboard.buttons[title].waitForExistence(timeout: 2) {
                    springboard.buttons[title].tap()
                }
            }
            XCTAssertTrue(app.textFields["searchField"].waitForExistence(timeout: 5), "voice search did not open the search")
            XCTAssertTrue(app.buttons["voiceSearch"].exists)
            app.buttons["closeSearch"].tap()
            XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 5))
        }
    }

    // MARK: Language, text size, speed

    @MainActor
    func testEnglishUser() {
        launch(language: "en", locale: "en_GB")
        step("EN 1 Map") {
            XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["mapSearch"].label.contains("Where do you want to go?"))
        }
        step("EN 2 Search and connections") {
            search("Konzil")
            pickPlace("Konzil")
            XCTAssertTrue(app.buttons["placeFrom"].label.contains("From"), "got \(app.buttons["placeFrom"].label)")
            XCTAssertTrue(element("Now").exists)
        }
        step("EN 3 Menu") {
            app.buttons["closePlace"].tap()
            app.buttons["moreHandle"].tap()
            XCTAssertTrue(element("Favourites").waitForExistence(timeout: 3))
            XCTAssertTrue(element("Tour with Seeri").exists)
        }
    }

    @MainActor
    func testVeryLargeText() {
        launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        step("AX 1 Map") {
            XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["mapSearch"].isHittable)
        }
        step("AX 2 Connections") {
            search("Konzil")
            pickPlace("Konzil")
            XCTAssertTrue(app.buttons["placeFrom"].isHittable)
        }
        step("AX 3 Menu") {
            app.buttons["closePlace"].tap()
            app.buttons["moreHandle"].tap()
            XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testLaunchTime() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            launch()
        }
    }
}
