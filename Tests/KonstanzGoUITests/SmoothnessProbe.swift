import XCTest

/// Drives the map while a -DKGMETER build counts dropped frames (FrameMeter writes Documents/meter.csv).
/// Only runs when asked: TEST_RUNNER_KG_PROBE=1, on a Release build with OTHER_SWIFT_FLAGS=-DKGMETER.
final class SmoothnessProbe: XCTestCase {
    @MainActor
    func testPanZoomAndSheets() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KG_PROBE"] != nil, "Only when asked")
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-onboarding.finished", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["mapSearch"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        func point(_ x: Double, _ y: Double) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }
        // The meter starts when the map's services do: about 6 s of waiting, then three stretches of 15 s.
        sleep(5)
        let deadline = { (seconds: Double) in Date().addingTimeInterval(seconds) }
        // 1: pan.
        var end = deadline(15), flip = false
        while Date() < end {
            flip.toggle()
            point(flip ? 0.8 : 0.2, 0.3).press(forDuration: 0.02, thenDragTo: point(flip ? 0.2 : 0.8, 0.45), withVelocity: .fast,
                                               thenHoldForDuration: 0)
        }
        // 2: zoom in, by double tap (it stops at the closest level, where the most detail is drawn).
        end = deadline(15)
        while Date() < end {
            point(0.5, 0.35).doubleTap()
            usleep(700_000)
        }
        // 3: a list over the moving map, dragged up and down.
        app.buttons["seeriMenu"].tap()
        end = deadline(15)
        while Date() < end {
            flip.toggle()
            point(0.5, flip ? 0.53 : 0.1).press(forDuration: 0.02, thenDragTo: point(0.5, flip ? 0.1 : 0.53), withVelocity: .default,
                                                thenHoldForDuration: 0)
        }
        sleep(2)
    }
}
