import Foundation
import KGCore

/// The map's limits and start view: Konstanz and around, zoom 12–18 (plan M3).
public enum MapRegion {
    public static let south = 47.645
    public static let north = 47.725
    public static let west = 9.08
    public static let east = 9.23
    public static let minZoom = 12.0
    public static let maxZoom = 18.0
    /// The start view without a location: the old town between Bahnhof and Sternenplatz.
    public static let center = Coordinate(latitude: 47.6615, longitude: 9.1745)
    /// A little way out, so more of the town shows (changed after testing on a phone).
    public static let startZoom = 13.8
    /// The user and the streets and stops around them, with room to see where to go (stops still show
    /// their bus tiles from 14.5).
    public static let userZoom = 14.6

    public static func contains(_ point: Coordinate) -> Bool {
        (south...north).contains(point.latitude) && (west...east).contains(point.longitude)
    }
}

/// The offline map's style, with its `asset://` URLs (written for Android) pointing at the bundled files,
/// saved to Caches so MapLibre can open it. Nothing in it points to the network (plan M1).
public enum MapStyleFile {
    public static func url(data: BundledData, dark: Bool) throws -> URL {
        let source = dark ? data.mapStyleDark : data.mapStyle
        var text = try String(contentsOf: source, encoding: .utf8)
        var folder = data.mapFolder.absoluteString
        if !folder.hasSuffix("/") { folder += "/" }
        text = text.replacingOccurrences(of: "asset://map/", with: folder)
        let target = URL.cachesDirectory.appending(path: dark ? "konstanz-style-dark.json" : "konstanz-style.json")
        try text.write(to: target, atomically: true, encoding: .utf8)
        return target
    }
}
