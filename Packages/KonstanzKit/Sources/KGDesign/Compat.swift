import SwiftUI

// The app runs on iOS 18 and newer. iOS 26 added Liquid Glass; on iOS 18–25 the same shapes get a
// blur material instead, so the app looks the same everywhere. Screens never check versions
// themselves: they use the helpers here.

public enum KGCompat {
    /// Launch argument that forces the iOS 18–25 look on iOS 26+, so both looks can be seen and
    /// snapshot-tested on one simulator: `-KGLegacyLook YES` (Debug builds only).
    public static let legacyLookKey = "KGLegacyLook"

    static var legacyLookFromLaunch: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: legacyLookKey)
        #else
        false
        #endif
    }

    /// True when real Liquid Glass is used: iOS 26+ and the legacy look not forced.
    public static func usesGlass(legacyLook: Bool) -> Bool {
        if legacyLook { return false }
        if #available(iOS 26, macOS 26, *) { return true }
        return false
    }
}

extension EnvironmentValues {
    /// Force the iOS 18–25 look (tests and previews set it; the app reads the launch argument).
    @Entry public var kgLegacyLook: Bool = KGCompat.legacyLookFromLaunch
}

extension View {
    /// A floating glass surface (tab bar, map buttons): Liquid Glass on iOS 26+, otherwise a blur
    /// material under the design's tab bar tint (`KGPalette.tabBar`).
    public func kgGlass<S: Shape>(in shape: S) -> some View {
        modifier(KGGlassModifier(shape: shape))
    }
}

private struct KGGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.kgLegacyLook) private var legacyLook

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *), KGCompat.usesGlass(legacyLook: legacyLook) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(KGColor.tabBar)
                }
            }
        }
    }
}
