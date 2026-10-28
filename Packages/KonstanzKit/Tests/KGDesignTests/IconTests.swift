import SwiftUI
import Testing
@testable import KGDesign

@Suite("SVG paths")
struct SVGPathTests {
    @Test func compactNumbers() throws {
        // From the design's "locate" arrow: "-.8.4" is −0.8, 0.4 and "1.5.1" is 1.5, 0.1.
        let path = try SVGPath.path("M20.5 3.5 3.8 10.6c-.8.4-.7 1.5.1 1.7l6.6 1.2 1.2 6.6c.2.8 1.3.9 1.7.1z")
        let box = path.boundingRect
        #expect(box.minX > 3 && box.maxX < 21 && box.minY > 3 && box.maxY < 21)
    }

    @Test func implicitLineAfterMove() throws {
        let path = try SVGPath.path("M0 0 10 0 10 10z")
        #expect(path.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func relativeCommandsAndHV() throws {
        let path = try SVGPath.path("m2 2h4v4H2z")
        #expect(path.boundingRect == CGRect(x: 2, y: 2, width: 4, height: 4))
    }

    @Test func arcsBulgeTheRightWay() throws {
        // Upper half circle from (4,12) to (20,12), radius 8: reaches up to y = 4, not down.
        let path = try SVGPath.path("M4 12a8 8 0 0 1 16 0")
        let box = path.boundingRect
        #expect(abs(box.minY - 4) < 0.01 && abs(box.maxY - 12) < 0.01)
        #expect(abs(box.minX - 4) < 0.01 && abs(box.maxX - 20) < 0.01)
    }

    @Test func arcFlagsWithoutSpaces() throws {
        // "a8 8 0 1 1-2.3-5.6" from the refresh icon parses the same as with spaces.
        let compact = try SVGPath.path("M20 12a8 8 0 1 1-2.3-5.6")
        let spaced = try SVGPath.path("M20 12a8 8 0 1 1 -2.3 -5.6")
        #expect(compact.boundingRect == spaced.boundingRect)
    }

    @Test func rejectsGarbage() {
        #expect(throws: SVGPath.Failure.self) { try SVGPath.path("M10 X") }
    }
}

@Suite("Icons")
struct IconTests {
    @Test("every icon's drawing reads", arguments: KGIcon.allCases)
    func readable(_ icon: KGIcon) {
        #expect(icon.isValid)
        #expect(!icon.drawing.elements.isEmpty)
    }

    @Test("every icon stays on the 24 pt grid", arguments: KGIcon.allCases)
    func onGrid(_ icon: KGIcon) {
        for element in icon.drawing.elements {
            let box = element.path.boundingRect
            #expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= 24 && box.maxY <= 24, "\(icon) \(box)")
        }
    }

    @Test func designIconsArePresent() {
        #expect(KGIcon.allCases.count == 43)
        for icon in [KGIcon.bus, .search, .map, .star, .more, .back, .walk, .locate, .layers, .swap] {
            #expect(KGIcon.allCases.contains(icon))
        }
    }
}
