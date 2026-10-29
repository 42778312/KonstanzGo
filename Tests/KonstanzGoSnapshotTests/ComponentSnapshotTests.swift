import KGDesign
import SnapshotTesting
import SwiftUI
import XCTest

/// Every component group from the design-system screen (plan Part B), in light, dark and at AX3.
final class ComponentSnapshotTests: XCTestCase {
    @MainActor
    private func check(_ part: ComponentGallery.Part, dark: Bool = false, size: DynamicTypeSize = .large,
                       name: String) {
        let view = ComponentGallery(part)
            .frame(width: 390)
            .environment(\.locale, Locale(identifier: "de_DE"))
            .environment(\.dynamicTypeSize, size)
            .transaction { $0.animation = nil }
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: traits), named: name,
                       testName: part.rawValue)
    }

    @MainActor func testButtons() { check(.buttons, name: "light"); check(.buttons, dark: true, name: "dark") }
    @MainActor func testTransit() { check(.transit, name: "light"); check(.transit, dark: true, name: "dark") }
    @MainActor func testTransitAX3() { check(.transit, size: .accessibility3, name: "ax3") }
    @MainActor func testControls() { check(.controls, name: "light"); check(.controls, dark: true, name: "dark") }
    @MainActor func testJourney() { check(.journey, name: "light"); check(.journey, dark: true, name: "dark") }
    @MainActor func testFeedback() { check(.feedback, name: "light") }
    @MainActor func testMap() { check(.map, name: "light"); check(.map, dark: true, name: "dark") }
}
