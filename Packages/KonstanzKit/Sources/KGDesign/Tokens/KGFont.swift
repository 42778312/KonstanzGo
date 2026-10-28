import CoreText
import SwiftUI

/// One text style of the design: Figtree at a size and weight, growing with Dynamic Type like `relativeTo`,
/// plus the letter-spacing, capitals and fixed-width digits some styles need. Sizes are measured from the
/// artboards (pt at 390 × 844).
public struct KGTextStyle: Sendable, Hashable {
    /// PostScript name of the Figtree instance ("Figtree-Bold").
    public var fontName: String
    public var size: CGFloat
    public var relativeTo: Font.TextStyle
    public var tracking: CGFloat = 0
    public var uppercase = false
    /// Times and minutes keep their width when the digits change ("tnum").
    public var monospacedDigits = false

    public var font: Font {
        KGFont.registerOnce()
        let font = Font.custom(fontName, size: size, relativeTo: relativeTo)
        return monospacedDigits ? font.monospacedDigit() : font
    }

    /// The same style at another size, for the few big numbers (`bigMinutes(44)`).
    public func sized(_ size: CGFloat) -> KGTextStyle {
        var copy = self
        copy.size = size
        return copy
    }
}

extension KGTextStyle {
    /// 40 Bold: start screen wordmark, "Alles bereit!".
    public static let hero = KGTextStyle(fontName: KGFont.bold, size: 40, relativeTo: .largeTitle)
    /// 32 ExtraBold: onboarding titles.
    public static let display = KGTextStyle(fontName: KGFont.extraBold, size: 32, relativeTo: .largeTitle)
    /// 28 Bold: screen titles ("Favoriten", "Mehr").
    public static let titleL = KGTextStyle(fontName: KGFont.bold, size: 28, relativeTo: .title)
    /// 22 ExtraBold: section and sheet titles ("In deiner Nähe").
    public static let title = KGTextStyle(fontName: KGFont.extraBold, size: 22, relativeTo: .title2)
    /// 19 Bold: route times, stop names in headers.
    public static let headline = KGTextStyle(fontName: KGFont.bold, size: 19, relativeTo: .title3)
    /// 17 Bold: row titles, stop names in cards.
    public static let bodyStrong = KGTextStyle(fontName: KGFont.bold, size: 17, relativeTo: .headline)
    /// 17 SemiBold: the search bar's text.
    public static let bodyMedium = KGTextStyle(fontName: KGFont.semiBold, size: 17, relativeTo: .body)
    /// 16 Regular: destinations, running text.
    public static let body = KGTextStyle(fontName: KGFont.regular, size: 16, relativeTo: .body)
    /// 16 Medium: button labels.
    public static let button = KGTextStyle(fontName: KGFont.medium, size: 16, relativeTo: .body)
    /// 15 SemiBold: links, row values.
    public static let callout = KGTextStyle(fontName: KGFont.semiBold, size: 15, relativeTo: .callout)
    /// 14 SemiBold: chips, walking time.
    public static let footnote = KGTextStyle(fontName: KGFont.semiBold, size: 14, relativeTo: .subheadline)
    /// 14 ExtraBold: line numbers on badges.
    public static let badge = KGTextStyle(fontName: KGFont.extraBold, size: 14, relativeTo: .subheadline)
    /// 13 Medium: secondary row text, platforms.
    public static let caption = KGTextStyle(fontName: KGFont.medium, size: 13, relativeTo: .footnote)
    /// 12 Bold, capitals, 1.5 pt apart: section headers ("ERGEBNISSE", "ZULETZT").
    public static let overline = KGTextStyle(fontName: KGFont.bold, size: 12, relativeTo: .caption, tracking: 1.5,
                                             uppercase: true)
    /// 11 Bold: tab bar labels.
    public static let tab = KGTextStyle(fontName: KGFont.bold, size: 11, relativeTo: .caption2)
    /// 17 ExtraBold, fixed-width digits: "3 Min." in rows.
    public static let minutes = KGTextStyle(fontName: KGFont.extraBold, size: 17, relativeTo: .headline,
                                            monospacedDigits: true)
    /// ExtraBold, fixed-width digits: the big countdowns (stop screen 26, journey 44).
    public static func bigMinutes(_ size: CGFloat) -> KGTextStyle {
        KGTextStyle(fontName: KGFont.extraBold, size: size, relativeTo: .largeTitle, monospacedDigits: true)
    }
}

extension View {
    /// Applies a design text style: font, letter-spacing and capitals.
    public func kgFont(_ style: KGTextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

/// Figtree (SIL Open Font License, see Resources/Fonts/Figtree-OFL.txt), bundled as one variable font
/// (weights 300–900) and registered for this process the first time a style is used.
public enum KGFont {
    public static let family = "Figtree"
    public static let regular = "Figtree-Regular"
    public static let medium = "Figtree-Medium"
    public static let semiBold = "Figtree-SemiBold"
    public static let bold = "Figtree-Bold"
    public static let extraBold = "Figtree-ExtraBold"

    /// True once the font is available (registered here or already by the system).
    public static let isRegistered: Bool = {
        guard let url = Bundle.module.url(forResource: "Figtree", withExtension: "ttf") else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        // "Already registered" is fine (a second bundle copy, or previews).
        return CTFontCreateWithName(bold as CFString, 17, nil).familyName == family
    }()

    @discardableResult
    public static func registerOnce() -> Bool { isRegistered }
}

private extension CTFont {
    var familyName: String { CTFontCopyFamilyName(self) as String }
}
