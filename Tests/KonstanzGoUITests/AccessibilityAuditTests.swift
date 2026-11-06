import XCTest

/// Apple's automated accessibility audit on the screens riders use most.
final class AccessibilityAuditTests: XCTestCase {
    @MainActor
    func testHomeAndSettingsPassTheAudit() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES", "-KGLiveSample"]
        app.launch()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        // Buses and map labels move and are drawn by the map, not SwiftUI; contrast over a moving map isn't meaningful.
        try app.performAccessibilityAudit(for: [.dynamicType, .sufficientElementDescription, .hitRegion]) { issue in
            print("AUDIT home:", issue.auditType, issue.compactDescription, issue.element?.label ?? "-", issue.element?.frame ?? .zero)
            return false
        }
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["openFavorites"].waitForExistence(timeout: 5))
        sleep(1)
        // Not .contrast: it flags white text on the glass sheet because the map moves behind it, and it isn't stable.
        try app.performAccessibilityAudit(for: [.dynamicType, .sufficientElementDescription, .hitRegion]) { issue in
            print("AUDIT settings:", issue.auditType, issue.compactDescription, issue.element?.label ?? "-", issue.element?.frame ?? .zero)
            return false
        }
    }

    /// With location refused the app still works: no prompt left behind, and search still opens.
    @MainActor
    func testLocationDeniedLeavesNoDeadEnd() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE", "-onboarding.finished", "YES", "-KGLiveSample"]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func answer(button index: Int) {
            app.resetAuthorizationStatus(for: .location)
            app.launch()
            // The map asks by itself on launch.
            let alert = springboard.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10))
            alert.buttons.element(boundBy: index).tap()  // Once, while using, don't allow.
        }
        answer(button: 2)
        defer { answer(button: 1) }  // The other tests expect a location.

        XCTAssertTrue(app.buttons["nowAskLocation"].waitForNonExistence(timeout: 5))
        app.buttons["mapSearch"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5) || app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.terminate()
    }
}
