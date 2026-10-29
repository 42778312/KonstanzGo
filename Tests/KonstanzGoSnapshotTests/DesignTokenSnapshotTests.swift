import KGDesign
import SnapshotTesting
import SwiftUI
import XCTest

/// The design tokens rendered on iOS: proves Figtree loads in the app and Dynamic Type scales it.
final class DesignTokenSnapshotTests: XCTestCase {
    /// Pinned, so the simulator's own appearance never changes the images.
    static let light = UITraitCollection(userInterfaceStyle: .light)

    @MainActor
    func testTypeScale() {
        let view = TypeSpecimen().frame(width: 390)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: Self.light))
    }

    @MainActor
    func testTypeScaleAtAX3() {
        // The largest sizes users pick: every style grows, none is cut off.
        let view = TypeSpecimen().frame(width: 390).dynamicTypeSize(.accessibility3)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: Self.light))
    }

    @MainActor
    func testTypeScaleDark() {
        let view = TypeSpecimen().frame(width: 390)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: UITraitCollection(userInterfaceStyle: .dark)))
    }

    @MainActor
    func testIcons() {
        let view = IconGallery().frame(width: 390)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: Self.light))
    }

    @MainActor
    func testSeeri() {
        let view = SeeriGallery().frame(width: 390)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: Self.light))
    }

    @MainActor
    func testWordmark() {
        let view = VStack(spacing: 24) {
            Wordmark()
            Wordmark(size: 44, on: .coral).padding(24).background(KGColor.coral)
        }
        .padding(24)
        .background(KGColor.surface)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: Self.light))
    }

    @MainActor
    func testColorSwatches() {
        let view = ColorSwatchesPreview().frame(width: 390)
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits, traits: Self.light))
    }
}
