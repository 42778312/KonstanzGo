import KGDesign
import SnapshotTesting
import SwiftUI
import XCTest

/// The design tokens rendered on iOS: proves Figtree loads in the app and Dynamic Type scales it.
final class DesignTokenSnapshotTests: XCTestCase {
    @MainActor
    func testTypeScale() {
        let view = TypeSpecimen().frame(width: 390)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
    }

    @MainActor
    func testTypeScaleAtAX3() {
        // The largest sizes users pick: every style grows, none is cut off.
        let view = TypeSpecimen().frame(width: 390).dynamicTypeSize(.accessibility3)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
    }

    @MainActor
    func testTypeScaleDark() {
        let view = TypeSpecimen().frame(width: 390)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: UITraitCollection(userInterfaceStyle: .dark)))
    }
}
