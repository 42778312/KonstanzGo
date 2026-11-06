import SwiftUI

/// One colour token: its light and dark values (sRGB, 0xRRGGBB, from the design's artboards 07–29 and
/// the brand board), with optional stronger values for "Increase Contrast".
public struct KGColorValue: Sendable, Hashable {
    public var light: UInt32
    public var dark: UInt32
    public var lightHighContrast: UInt32?
    public var darkHighContrast: UInt32?
    /// Alpha for both modes (the tab bar and glass fills are see-through).
    public var opacity: Double

    public init(_ light: UInt32, dark: UInt32? = nil, highContrast: UInt32? = nil, darkHighContrast: UInt32? = nil,
                opacity: Double = 1) {
        self.light = light
        self.dark = dark ?? light
        lightHighContrast = highContrast
        self.darkHighContrast = darkHighContrast
        self.opacity = opacity
    }

    public func value(dark isDark: Bool, highContrast: Bool = false) -> UInt32 {
        switch (isDark, highContrast) {
        case (false, false): light
        case (true, false): dark
        case (false, true): lightHighContrast ?? light
        case (true, true): darkHighContrast ?? dark
        }
    }
}

/// The design's colours. Screens use these names only, never raw values (plan rule 4, enforced by SwiftLint).
/// Each pair of text and background colours the app uses is checked for contrast in `KGDesignTests`.
public enum KGPalette {
    // MARK: Brand
    /// Seeri, bus markers, app icon, the active tab icon. Not for small text (3.3:1 on white).
    public static let coral = KGColorValue(0xF05A62, dark: 0xFF5A62)
    /// Fills that carry white text: bus pills on the map (4.9:1).
    public static let coralDeep = KGColorValue(0xD1343E)
    /// The Swiss buses to Kreuzlingen on the map: yellow like the buses there.
    public static let kreuzlingen = KGColorValue(0xFFCC00)
    public static let coralPressed = KGColorValue(0xC93D45)
    /// Fill of the active tab icon.
    public static let coralTint = KGColorValue(0xFFCDD0, dark: 0x5A2A2E)

    // MARK: Ink
    public static let ink = KGColorValue(0x000000, dark: 0xFFFFFF)
    /// Secondary text (7.6:1 on white).
    public static let ink2 = KGColorValue(0x545454, dark: 0xE0E0E0)
    /// Captions and placeholders. The design's #757575 is 4.3:1 on its grey cards; #6B6B6B passes on both.
    public static let ink3 = KGColorValue(0x6B6B6B, dark: 0x9E9E9E, highContrast: 0x4A4A4A, darkHighContrast: 0xC4C4C4)
    /// Decoration only (chevrons, empty states' lines), never text.
    public static let ink4 = KGColorValue(0x9E9E9E, dark: 0x5A5A5A)
    public static let chevron = KGColorValue(0xC7C7CC, dark: 0x5A5A5A, highContrast: 0x8E8E93)

    // MARK: Surfaces
    public static let surface = KGColorValue(0xFFFFFF, dark: 0x181818)
    /// Grouped cards, the search field, "In deiner Nähe".
    public static let card = KGColorValue(0xF6F6F6, dark: 0x242424)
    public static let pressed = KGColorValue(0xEEEEEE, dark: 0x2A2A2A)
    public static let line = KGColorValue(0xE2E2E2, dark: 0x2D2D2D, highContrast: 0xB0B0B0, darkHighContrast: 0x555555)
    public static let switchOff = KGColorValue(0xE9E9EB, dark: 0x39393D)
    public static let handle = KGColorValue(0xD1D1D6, dark: 0x5A5A5A)
    /// The floating tab bar's fill under its blur (iOS 18–25).
    public static let tabBar = KGColorValue(0xFFFFFF, dark: 0x242424, opacity: 0.92)

    // MARK: Status
    /// Live dots and success fills. Not for text (3.9:1); text uses `liveText`.
    public static let live = KGColorValue(0x05944F)
    /// Green text: 5.4:1 on white, 5.0:1 on cards, 4.8:1 on `liveTint`.
    public static let liveText = KGColorValue(0x047A41, dark: 0x5BD08F)
    public static let liveTint = KGColorValue(0xE6F4EC, dark: 0x203126)
    /// The user's position, links (4.6:1 on white).
    public static let location = KGColorValue(0x276EF1, dark: 0x0A84FF)
    public static let locationTint = KGColorValue(0xE9F0FE, dark: 0x1C2A44)
    public static let warn = KGColorValue(0xFF9500, dark: 0xFF9F0A)

    // MARK: Line badges
    public static let lineFill = KGColorValue(0xFFC043)
    /// Text on `lineFill` (8.5:1).
    public static let onLine = KGColorValue(0x3A2A00)
    public static let lineTint = KGColorValue(0xFFF4D1, dark: 0x3A3220)
    /// Text on `lineTint` tags ("Schnellste", "Erster Bus 05:42").
    public static let lineText = KGColorValue(0x8A6200, dark: 0xFFC043)

    // Settings icon tiles (screen 13), iOS system colours.
    public static let tileRed = KGColorValue(0xFF3B30, dark: 0xFF453A)
    public static let tileIndigo = KGColorValue(0x5856D6, dark: 0x5E5CE6)
    public static let tileBlack = KGColorValue(0x000000, dark: 0x3A3A3C)
    /// The search field's clear button.
    public static let clearButton = KGColorValue(0xAEAEB2, dark: 0x636366)

    // Onboarding illustrations (screens 01–06).
    /// The town silhouette behind the lake (02).
    public static let sceneTown = KGColorValue(0xE6EEF6, dark: 0x26313B)
    /// Gulls over the lake (02).
    public static let sceneGull = KGColorValue(0x9FB7C4, dark: 0x6E8794)
    /// The start screen's darker sea band (01).
    public static let startSea = KGColorValue(0xD9464F)
    /// The sample notification banner (05), iOS's own banner grey.
    public static let banner = KGColorValue(0xF2F2F7, dark: 0x2C2C2E, opacity: 0.96)
    /// The trail behind the bus on the search demo (04).
    public static let trail = KGColorValue(0xFFC2C6, dark: 0x6A3438)

    // MARK: Seeri
    public static let seeriBody = KGColorValue(0xF05A62)
    public static let seeriFace = KGColorValue(0xEAF6FF)
    public static let seeriDark = KGColorValue(0x33283A)
    public static let seeriCheek = KGColorValue(0xFFB3A7)
    public static let seeriHeadlight = KGColorValue(0xFFE7A8)
    /// Headlight rim and grille.
    public static let seeriTrim = KGColorValue(0xC93D45)
    /// Sleepy Seeri (screen 23): dimmed face screen and headlights off.
    public static let seeriFaceDim = KGColorValue(0xDCE6F2)
    public static let seeriHeadlightOff = KGColorValue(0xB8A9A8)
    /// Witch hat (screen 29).
    public static let witchHat = KGColorValue(0x3B1F5C)

    // MARK: Map (light and dark styles)
    /// The stop sign on the map: dark blue, so stops stay calm next to the coral buses.
    public static let stopSign = KGColorValue(0x24405F)
    public static let mapLand = KGColorValue(0xF2F1ED, dark: 0x1E1E1E)
    public static let mapWater = KGColorValue(0xB9D8E8, dark: 0x182D38)
    public static let mapWaterLabel = KGColorValue(0x3F6FB0, dark: 0x6E9BD6)
    public static let mapPark = KGColorValue(0xD8E8D2, dark: 0x203126)
    public static let mapBuilding = KGColorValue(0xE5E2DE, dark: 0x2A2A2A)
    public static let mapRoadCasing = KGColorValue(0xD5D3CF, dark: 0x2D2D2D)
    public static let mapRoad = KGColorValue(0xFFFFFF, dark: 0x3A3A3A)
    public static let mapLabel = KGColorValue(0x757575, dark: 0x9E9E9E)

    // MARK: Halloween (screen 29)
    public static let halloweenNight = KGColorValue(0x2A1638)
    public static let halloweenGround = KGColorValue(0x1F0F2C)
    public static let halloweenTown = KGColorValue(0x1A0C24)
    public static let halloweenMoon = KGColorValue(0xFFB067)
    public static let halloweenWave = KGColorValue(0x5B3478)
    public static let halloweenGreeting = KGColorValue(0xFFD9B0)
    public static let halloweenDate = KGColorValue(0xD9C4E8)
}

/// The tokens as SwiftUI colours that follow light/dark mode and "Increase Contrast".
public enum KGColor {
    public static let coral = Color(KGPalette.coral)
    public static let coralDeep = Color(KGPalette.coralDeep)
    public static let kreuzlingen = Color(KGPalette.kreuzlingen)
    public static let coralPressed = Color(KGPalette.coralPressed)
    public static let coralTint = Color(KGPalette.coralTint)
    public static let ink = Color(KGPalette.ink)
    public static let ink2 = Color(KGPalette.ink2)
    public static let ink3 = Color(KGPalette.ink3)
    public static let ink4 = Color(KGPalette.ink4)
    public static let chevron = Color(KGPalette.chevron)
    public static let surface = Color(KGPalette.surface)
    public static let card = Color(KGPalette.card)
    /// Lists and cards on glass (the stop sheet's look): a light veil over whatever is behind, never solid black.
    public static let glassFill = Color.white.opacity(0.08)
    public static let stopSign = Color(KGPalette.stopSign)
    public static let pressed = Color(KGPalette.pressed)
    public static let line = Color(KGPalette.line)
    public static let switchOff = Color(KGPalette.switchOff)
    public static let handle = Color(KGPalette.handle)
    public static let tabBar = Color(KGPalette.tabBar)
    public static let live = Color(KGPalette.live)
    public static let liveText = Color(KGPalette.liveText)
    public static let liveTint = Color(KGPalette.liveTint)
    public static let location = Color(KGPalette.location)
    public static let locationTint = Color(KGPalette.locationTint)
    public static let warn = Color(KGPalette.warn)
    public static let lineFill = Color(KGPalette.lineFill)
    public static let onLine = Color(KGPalette.onLine)
    public static let lineTint = Color(KGPalette.lineTint)
    public static let lineText = Color(KGPalette.lineText)
    public static let tileRed = Color(KGPalette.tileRed)
    public static let tileIndigo = Color(KGPalette.tileIndigo)
    public static let tileBlack = Color(KGPalette.tileBlack)
    public static let clearButton = Color(KGPalette.clearButton)
    public static let mapLand = Color(KGPalette.mapLand)
    public static let mapWater = Color(KGPalette.mapWater)
    public static let mapWaterLabel = Color(KGPalette.mapWaterLabel)
    public static let mapPark = Color(KGPalette.mapPark)
    public static let mapBuilding = Color(KGPalette.mapBuilding)
    public static let mapRoadCasing = Color(KGPalette.mapRoadCasing)
    public static let mapRoad = Color(KGPalette.mapRoad)
    public static let mapLabel = Color(KGPalette.mapLabel)
    public static let sceneTown = Color(KGPalette.sceneTown)
    public static let sceneGull = Color(KGPalette.sceneGull)
    public static let startSea = Color(KGPalette.startSea)
    public static let banner = Color(KGPalette.banner)
    public static let trail = Color(KGPalette.trail)
    public static let seeriBody = Color(KGPalette.seeriBody)
    public static let seeriFace = Color(KGPalette.seeriFace)
    public static let seeriDark = Color(KGPalette.seeriDark)
    public static let seeriCheek = Color(KGPalette.seeriCheek)
    public static let seeriHeadlight = Color(KGPalette.seeriHeadlight)
    public static let seeriTrim = Color(KGPalette.seeriTrim)
    public static let seeriFaceDim = Color(KGPalette.seeriFaceDim)
    public static let seeriHeadlightOff = Color(KGPalette.seeriHeadlightOff)
    public static let witchHat = Color(KGPalette.witchHat)
    public static let halloweenNight = Color(KGPalette.halloweenNight)
    public static let halloweenGround = Color(KGPalette.halloweenGround)
    public static let halloweenTown = Color(KGPalette.halloweenTown)
    public static let halloweenMoon = Color(KGPalette.halloweenMoon)
    public static let halloweenWave = Color(KGPalette.halloweenWave)
    public static let halloweenGreeting = Color(KGPalette.halloweenGreeting)
    public static let halloweenDate = Color(KGPalette.halloweenDate)
    /// Pure white, the same in dark mode: text and icons on coral, black and photo fills.
    public static let white = Color(KGColorValue(0xFFFFFF))
}

extension Color {
    /// A colour that follows light/dark mode and "Increase Contrast".
    public init(_ token: KGColorValue) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: token.value(dark: traits.userInterfaceStyle == .dark,
                                     highContrast: traits.accessibilityContrast == .high), opacity: token.opacity)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            // macOS is only used for tests and previews; contrast follows the system setting there.
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            return NSColor(rgb: token.value(dark: dark, highContrast: high), opacity: token.opacity)
        })
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgb: UInt32, opacity: Double) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: opacity)
    }
}
#else
extension NSColor {
    convenience init(rgb: UInt32, opacity: Double) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: opacity)
    }
}
#endif
