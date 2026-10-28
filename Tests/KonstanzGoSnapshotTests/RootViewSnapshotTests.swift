import KGCore
import KGDesign
import KGFeatures
import SnapshotTesting
import SwiftUI
import XCTest

/// Screen snapshots at the design's frame size (390×844 pt). Reference images live in
/// __Snapshots__/ next to this file. To re-record after an intended change, set `record: .all`.
///
/// Milestone 0: only the placeholder root view, to prove the snapshot pipeline works.
final class RootViewSnapshotTests: XCTestCase {
    static let designFrame = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 390, height: 844),
        traits: UITraitCollection(displayScale: 3)
    )

    let info = TimetableInfo(
        feedVersion: "20261011",
        validFrom: DateComponents(year: 2026, month: 7, day: 12),
        validUntil: DateComponents(year: 2026, month: 12, day: 12),
        attribution: "Datensatz der NVBW GmbH",
        stations: 142, platforms: 263, cityLines: 18, trips: 3380
    )

    @MainActor
    func testRootLight() {
        let view = RootView(info: info).environment(\.locale, Locale(identifier: "de_DE"))
        assertSnapshot(of: UIHostingController(rootView: view), as: .image(on: Self.designFrame))
    }

    @MainActor
    func testRootDark() {
        let view = RootView(info: info).environment(\.locale, Locale(identifier: "de_DE"))
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        assertSnapshot(of: UIHostingController(rootView: view), as: .image(on: Self.designFrame, traits: dark))
    }
}
