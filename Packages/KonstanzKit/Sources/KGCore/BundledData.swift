import Foundation

/// The offline data files shipped in the app bundle under `Data/` (built by `DataPipeline/build.sh`).
public struct BundledData: Sendable {
    public let root: URL
    /// Newer files downloaded since the app shipped (`DataStore`), used instead of the bundle's where present.
    public let overlay: URL?

    public init(root: URL, overlay: URL? = nil) {
        self.root = root
        self.overlay = overlay
    }

    private func file(_ path: String) -> URL {
        if let updated = overlay?.appending(path: path), FileManager.default.fileExists(atPath: updated.path) {
            return updated
        }
        return root.appending(path: path)
    }

    /// The same data without the downloaded files.
    public var bundled: BundledData { BundledData(root: root) }

    private var feedVersion: String {
        (try? TimetableInfo.read(from: root.appending(path: "timetable.db")))?.feedVersion ?? ""
    }

    /// For the app at launch: the bundle plus downloaded data, if there is any to try.
    public static func forApp(store: DataStore = .shared) -> BundledData? {
        guard let data = BundledData(bundle: .main) else { return nil }
        return BundledData(root: data.root, overlay: store.overlayForLaunch(bundledFeed: data.feedVersion))
    }

    /// The `Data` folder inside the given bundle, or nil if it is missing.
    public init?(bundle: Bundle) {
        guard let url = bundle.url(forResource: "Data", withExtension: nil) else { return nil }
        self.init(root: url)
    }

    /// The data for this process: the app's own bundle, or, in the widget extension, the containing app's
    /// (an extension may read the app it ships in).
    public static func forCurrentProcess() -> BundledData? {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard let data = BundledData(bundle: .main) ?? Bundle(url: app).flatMap({ BundledData(bundle: $0) }) else { return nil }
        return BundledData(root: data.root, overlay: DataStore.shared.overlayForReading(bundledFeed: data.feedVersion))
    }

    public var timetable: URL { file("timetable.db") }
    public var mapTiles: URL { root.appending(path: "map/konstanz.pmtiles") }
    public var mapStyle: URL { root.appending(path: "map/style.json") }
    public var mapStyleDark: URL { root.appending(path: "map/style-dark.json") }
    public var mapFolder: URL { root.appending(path: "map", directoryHint: .isDirectory) }
    public var mapFonts: URL { root.appending(path: "map/fonts") }
    public var walkGraph: URL { file("walk/konstanz-walk.bin") }
    public var searchIndex: URL { file("search/places.tsvz") }

    public var allFiles: [URL] { [timetable, mapTiles, mapStyle, mapStyleDark, walkGraph, searchIndex] }
}
