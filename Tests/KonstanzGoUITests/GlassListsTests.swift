import XCTest

/// Walks every list, at half and full height, and keeps a picture of each to check they're all glass.
final class GlassListsTests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Pulls the sheet up to full height by the handle.
    @MainActor
    private func pullUp(above element: XCUIElement) {
        let window = app.windows.firstMatch
        let top = element.frame.minY - 24
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: top))
        start.press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        sleep(1)
    }

    @MainActor
    func testEveryListIsGlass() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES",
                                "-KGLiveSample"]
        app.launch()
        XCTAssertTrue(app.buttons["moreHandle"].waitForExistence(timeout: 10))

        // More, half and full, and its own screens.
        app.buttons["moreHandle"].tap()
        let favorites = app.buttons["openFavorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        sleep(1)
        shot("01-more-half")
        pullUp(above: favorites)
        shot("02-more-full")
        // Waits, as the sheet can still be settling after the pull.
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        favorites.tap()
        sleep(1)
        shot("03-favourites")
        app.buttons.matching(NSPredicate(format: "label == 'Mehr'")).firstMatch.tap()
        sleep(1)
        let offline = app.buttons["offlineCard"]
        XCTAssertTrue(offline.waitForExistence(timeout: 3))
        offline.tap()
        sleep(1)
        shot("04-offline")
        app.buttons.matching(NSPredicate(format: "label == 'Mehr'")).firstMatch.tap()
        sleep(1)
        let privacy = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Datenschutz'")).firstMatch
        privacy.tap()
        sleep(1)
        shot("05-privacy")
        app.buttons.matching(NSPredicate(format: "label == 'Mehr'")).firstMatch.tap()
        sleep(1)
        let about = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Über'")).firstMatch
        about.tap()
        sleep(1)
        shot("06-about")
        app.terminate()

        // Notices, half and full; a stop, half and full.
        app.launch()
        let seeri = app.buttons["seeriMenu"]
        XCTAssertTrue(seeri.waitForExistence(timeout: 10))
        seeri.tap()
        let close = app.buttons["closeNotices"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        sleep(1)
        shot("07-notices-half")
        pullUp(above: close)
        shot("08-notices-full")
        let stop = app.buttons["alternativeStop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 3))
        stop.tap()
        let closeStation = app.buttons["closeStation"]
        XCTAssertTrue(closeStation.waitForExistence(timeout: 5))
        sleep(1)
        shot("09-stop-half")
        pullUp(above: closeStation)
        shot("10-stop-full")
        let time = app.buttons["stationTime"]
        if time.exists {
            time.tap()
            sleep(1)
            shot("11-time-picker")
        }
        app.terminate()

        // Search, a place's connections full, and When & how.
        app.launch()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        app.buttons["mapSearch"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        sleep(1)
        shot("12-search")
        field.tap()
        field.typeText("Dingelsdorf")
        sleep(1)
        shot("13-search-results")
        let place = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Dingelsdorf'")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        let from = app.buttons["placeFrom"]
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        sleep(2)
        shot("14-place-half")
        pullUp(above: from)
        shot("15-place-full")
    }
}
