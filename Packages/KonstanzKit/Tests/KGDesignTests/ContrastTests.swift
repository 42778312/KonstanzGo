import Foundation
import Testing
@testable import KGDesign

/// Every text colour on every background the screens put it on (plan A1.4): 4.5:1 for text,
/// 3:1 for large bold text (24 pt+) and icons. Fails the build when a token change breaks one.
@Suite("Contrast")
struct ContrastTests {
    struct Pair: CustomTestStringConvertible, Sendable {
        let name: String
        let text: KGColorValue
        let background: KGColorValue
        let minimum: Double
        var testDescription: String { name }
    }

    static let body = 4.5
    static let large = 3.0

    static let pairs: [Pair] = [
        Pair(name: "ink on surface", text: KGPalette.ink, background: KGPalette.surface, minimum: body),
        Pair(name: "ink on card", text: KGPalette.ink, background: KGPalette.card, minimum: body),
        Pair(name: "ink2 on surface", text: KGPalette.ink2, background: KGPalette.surface, minimum: body),
        Pair(name: "ink2 on card", text: KGPalette.ink2, background: KGPalette.card, minimum: body),
        Pair(name: "ink3 on surface", text: KGPalette.ink3, background: KGPalette.surface, minimum: body),
        Pair(name: "ink3 on card", text: KGPalette.ink3, background: KGPalette.card, minimum: body),
        Pair(name: "ink3 on pressed", text: KGPalette.ink3, background: KGPalette.pressed, minimum: body),
        Pair(name: "liveText on surface", text: KGPalette.liveText, background: KGPalette.surface, minimum: body),
        Pair(name: "liveText on card", text: KGPalette.liveText, background: KGPalette.card, minimum: body),
        Pair(name: "liveText on liveTint", text: KGPalette.liveText, background: KGPalette.liveTint, minimum: body),
        Pair(name: "location (links) on surface", text: KGPalette.location, background: KGPalette.surface, minimum: body),
        Pair(name: "onLine on lineFill", text: KGPalette.onLine, background: KGPalette.lineFill, minimum: body),
        Pair(name: "white on coralDeep (bus pills)", text: KGColorValue(0xFFFFFF), background: KGPalette.coralDeep,
             minimum: body),
        Pair(name: "white on ink (black buttons)", text: KGColorValue(0xFFFFFF), background: KGColorValue(0x000000),
             minimum: body),
        Pair(name: "white on coral (large wordmark only)", text: KGColorValue(0xFFFFFF), background: KGPalette.coral,
             minimum: large),
        Pair(name: "coral icons on surface", text: KGPalette.coral, background: KGPalette.surface, minimum: large),
        Pair(name: "live dot on surface", text: KGPalette.live, background: KGPalette.surface, minimum: large),
        Pair(name: "Halloween greeting", text: KGPalette.halloweenGreeting, background: KGPalette.halloweenNight,
             minimum: body),
        Pair(name: "Halloween date", text: KGPalette.halloweenDate, background: KGPalette.halloweenNight, minimum: body),
    ]

    @Test("light mode", arguments: pairs)
    func light(_ pair: Pair) {
        check(pair, dark: false, highContrast: false)
    }

    @Test("dark mode", arguments: pairs)
    func dark(_ pair: Pair) {
        check(pair, dark: true, highContrast: false)
    }

    @Test("Increase Contrast", arguments: pairs)
    func highContrast(_ pair: Pair) {
        check(pair, dark: false, highContrast: true)
        check(pair, dark: true, highContrast: true)
    }

    @Test func formulaMatchesKnownValues() {
        #expect(abs(Contrast.ratio(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(Contrast.ratio(0x757575, 0xFFFFFF) - 4.61) < 0.01)
        #expect(abs(Contrast.ratio(0x05944F, 0xFFFFFF) - 3.92) < 0.01)
    }

    func check(_ pair: Pair, dark: Bool, highContrast: Bool) {
        let ratio = Contrast.ratio(pair.text.value(dark: dark, highContrast: highContrast),
                                   pair.background.value(dark: dark, highContrast: highContrast))
        #expect(ratio >= pair.minimum, "\(pair.name): \(String(format: "%.2f", ratio)):1, needs \(pair.minimum):1")
    }
}

/// WCAG 2 contrast ratio.
enum Contrast {
    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        let lighter = max(luminance(first), luminance(second)), darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let fraction = Double(value & 0xFF) / 255
            return fraction <= 0.039_28 ? fraction / 12.92 : pow((fraction + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb >> 16) + 0.7152 * channel(rgb >> 8) + 0.0722 * channel(rgb)
    }
}
