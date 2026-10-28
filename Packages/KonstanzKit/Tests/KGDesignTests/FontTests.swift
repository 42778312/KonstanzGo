import CoreText
import SwiftUI
import Testing
@testable import KGDesign

@Suite("Figtree")
struct FontTests {
    @Test func registersFromThePackage() {
        #expect(KGFont.registerOnce())
    }

    @Test("every weight resolves to Figtree, not a fallback",
          arguments: [KGFont.regular, KGFont.medium, KGFont.semiBold, KGFont.bold, KGFont.extraBold])
    func weightResolves(_ name: String) {
        KGFont.registerOnce()
        let font = CTFontCreateWithName(name as CFString, 17, nil)
        #expect(CTFontCopyFamilyName(font) as String == KGFont.family)
        #expect(CTFontCopyPostScriptName(font) as String == name)
    }

    @Test func weightsGetHeavier() {
        KGFont.registerOnce()
        func weight(_ name: String) -> Double {
            let traits = CTFontCopyTraits(CTFontCreateWithName(name as CFString, 17, nil)) as? [CFString: Any]
            return (traits?[kCTFontWeightTrait] as? Double) ?? 0
        }
        let weights = [KGFont.regular, KGFont.medium, KGFont.semiBold, KGFont.bold, KGFont.extraBold].map(weight)
        #expect(weights == weights.sorted())
        #expect(Set(weights).count == 5)
    }

    @Test func styleScaleFollowsTheDesign() {
        #expect(KGTextStyle.hero.size == 40)
        #expect(KGTextStyle.title.size == 22 && KGTextStyle.title.fontName == KGFont.extraBold)
        #expect(KGTextStyle.overline.uppercase && KGTextStyle.overline.tracking == 1.5)
        #expect(KGTextStyle.minutes.monospacedDigits)
        #expect(KGTextStyle.bigMinutes(44).size == 44)
    }

    @Test func licenceShipsWithTheFont() throws {
        let url = try #require(Bundle.module.url(forResource: "Figtree-OFL", withExtension: "txt"))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("SIL Open Font License"))
    }
}
