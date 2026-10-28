import SwiftUI

/// Corner radii from the artboards. Corners are `.continuous` (the iOS look) everywhere.
public enum KGRadius {
    public static let xs: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    /// Buttons, map buttons.
    public static let large: CGFloat = 14
    /// The map's search bar.
    public static let search: CGFloat = 18
    /// Cards, the sheet's top corners.
    public static let card: CGFloat = 20
}

/// Spacing on the design's 2/4 pt grid.
public enum KGSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 6
    public static let small: CGFloat = 8
    public static let compact: CGFloat = 10
    public static let medium: CGFloat = 12
    public static let mediumLarge: CGFloat = 14
    /// Side margin of every screen.
    public static let screen: CGFloat = 16
    public static let large: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

/// Fixed sizes from the artboards.
public enum KGSize {
    /// List rows (departures, settings).
    public static let row: CGFloat = 44
    /// Smallest touch target (Apple HIG); drawn controls may be smaller but are hit this big.
    public static let touch: CGFloat = 44
    public static let button: CGFloat = 56
    public static let searchBar: CGFloat = 56
    public static let mapButton: CGFloat = 48
    public static let badgeHeight: CGFloat = 26
    public static let badgeMinWidth: CGFloat = 36
    public static let tabItem = CGSize(width: 96, height: 54)
    /// 5 pt padding around the tab items.
    public static let tabBarPadding: CGFloat = 5
    /// Gap between the tab bar and the bottom safe area.
    public static let tabBarBottom: CGFloat = 26
    public static let sheetHandle = CGSize(width: 36, height: 5)
    public static let settingsIcon: CGFloat = 30
}

extension Shape where Self == RoundedRectangle {
    /// A rounded rectangle with the iOS continuous corner curve.
    public static func kgRounded(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
