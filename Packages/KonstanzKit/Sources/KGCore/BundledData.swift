import Foundation

/// The offline data files shipped in the app bundle under `Data/` (built by `DataPipeline/build.sh`).
public struct BundledData: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The `Data` folder inside the given bundle, or nil if it is missing.
    public init?(bundle: Bundle) {
        guard let url = bundle.url(forResource: "Data", withExtension: nil) else { return nil }
        self.init(root: url)
    }

    /// The data for this process: the app's own bundle, or, in the widget extension, the containing app's
    /// (an extension may read the app it ships in).
    public static func forCurrentProcess() -> BundledData? {
        if let data = BundledData(bundle: .main) { return data }
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app).flatMap { BundledData(bundle: $0) }
    }

    public var timetable: URL { root.appending(path: "timetable.db") }
    public var mapTiles: URL { root.appending(path: "map/konstanz.pmtiles") }
    public var mapStyle: URL { root.appending(path: "map/style.json") }
    public var mapStyleDark: URL { root.appending(path: "map/style-dark.json") }
    public var mapFolder: URL { root.appending(path: "map", directoryHint: .isDirectory) }
    public var mapFonts: URL { root.appending(path: "map/fonts") }
    public var walkGraph: URL { root.appending(path: "walk/konstanz-walk.bin") }
    public var searchIndex: URL { root.appending(path: "search/places.tsvz") }

    public var allFiles: [URL] { [timetable, mapTiles, mapStyle, mapStyleDark, walkGraph, searchIndex] }
}
