import Foundation

private final class KGDesignBundleFinder {}

extension Bundle {
    /// This package's resources (Figtree, the string catalog). Found here instead of SwiftPM's `Bundle.module`,
    /// which stops the process when the bundle is not where it expects; Xcode's iOS test runner is such a
    /// place, and the widget extension could be. Without the bundle, text falls back to the German keys.
    static let kgDesign: Bundle = {
        let name = "KonstanzKit_KGDesign.bundle"
        let owner = Bundle(for: KGDesignBundleFinder.self)
        var places = [Bundle.main.resourceURL, Bundle.main.bundleURL, owner.resourceURL, owner.bundleURL,
                      owner.bundleURL.deletingLastPathComponent()]
        places += (Bundle.allBundles + Bundle.allFrameworks).flatMap { [$0.resourceURL, $0.bundleURL] }
        for place in places.compactMap({ $0 }) {
            if let bundle = Bundle(url: place.appending(path: name)) { return bundle }
        }
        return owner
    }()
}
