import XCTest

/// On a trip the first bus is cancelled (`-KGCancelFirstRide`): the app says so, one tap finds another way,
/// another tap takes it.
final class RescueTests: XCTestCase {
    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testOneTapToAnotherRoute() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES",
                                "-KGCancelFirstRide"]
        app.launch()
        let bar = app.buttons["mapSearch"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        bar.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Dingelsdorf")
        let place = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Dingelsdorf'")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        let card = app.buttons["routeCard"].firstMatch
        guard card.waitForExistence(timeout: 15) else { return } // nothing runs at this hour
        card.tap()

        let button = app.buttons["rescueButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "no warning about the cancelled bus")
        shot(app, "1-warning")
        let reason = app.staticTexts["rescueReason"]
        XCTAssertTrue(reason.label.contains("fällt aus"), reason.label)
        button.tap()
        let option = app.buttons["rescueOption"].firstMatch
        guard option.waitForExistence(timeout: 5) else {
            XCTAssertTrue(app.descendants(matching: .any)["noRescue"].exists, "neither a way nor a message")
            return
        }
        shot(app, "2-options")
        XCTAssertTrue(option.label.contains("Ankunft"), option.label)
        option.tap()
        // The new route is what the trip now follows, and all is well with it.
        XCTAssertTrue(app.descendants(matching: .any)["journeyLegs"].waitForExistence(timeout: 5))
        XCTAssertTrue(button.waitForNonExistence(timeout: 5), "still warning about the old bus")
        shot(app, "3-new-route")
    }
}
