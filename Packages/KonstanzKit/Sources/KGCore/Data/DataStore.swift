import Foundation

/// Newer data files downloaded after the app shipped, in the App Group folder so the widgets read them too. A
/// new set never replaces files in use: it goes into its own folder and counts from the next launch. If the app
/// can't start with it, the next launch goes back to the previous set or the bundle.
public struct DataStore: Sendable {
    struct Pointer: Codable, Equatable {
        var version: Int
        var feedVersion: String
        /// The app has started with this set.
        var confirmed: Bool
        /// A launch has tried this set; a second try without `confirmed` means that launch failed.
        var tried = false
        /// The set to go back to.
        var previous: Int?
        var previousFeedVersion: String?
    }

    public let folder: URL
    private var pointerFile: URL { folder.appending(path: "current.json") }

    public init(folder: URL) {
        self.folder = folder
    }

    /// The store the app and its widgets share.
    public static var shared: DataStore {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: UserStore.appGroup)
            ?? URL.applicationSupportDirectory
        return DataStore(folder: base.appending(path: "data", directoryHint: .isDirectory))
    }

    private func directory(_ version: Int) -> URL {
        folder.appending(path: "v\(version)", directoryHint: .isDirectory)
    }

    var pointer: Pointer? {
        (try? Data(contentsOf: pointerFile)).flatMap { try? JSONDecoder().decode(Pointer.self, from: $0) }
    }

    private func save(_ pointer: Pointer?) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let pointer {
            try JSONEncoder().encode(pointer).write(to: pointerFile, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: pointerFile)
        }
    }

    /// The version installed, whether or not it has been started yet.
    public var currentVersion: Int? { pointer?.version }

    /// For the app at launch: the folder to read, counting this launch as a try of an unconfirmed set. Nil means
    /// the bundle. A set older than the bundle's timetable is ignored, as after an app update.
    public func overlayForLaunch(bundledFeed: String) -> URL? {
        guard var current = pointer else { return nil }
        if !current.confirmed {
            if current.tried {
                rollBack(current)
                return overlayForLaunch(bundledFeed: bundledFeed)
            }
            current.tried = true
            try? save(current)
        }
        return current.feedVersion >= bundledFeed ? directory(current.version) : nil
    }

    /// For the widgets, which don't count as a launch: only a set the app has started with.
    public func overlayForReading(bundledFeed: String) -> URL? {
        guard let current = pointer else { return nil }
        if current.confirmed {
            return current.feedVersion >= bundledFeed ? directory(current.version) : nil
        }
        guard let previous = current.previous, let feed = current.previousFeedVersion else { return nil }
        return feed >= bundledFeed ? directory(previous) : nil
    }

    /// The app has started with the current set.
    public func confirm() {
        guard var current = pointer, !current.confirmed else { return }
        current.confirmed = true
        try? save(current)
    }

    /// Goes back from a set that didn't start.
    public func rollBack() {
        if let current = pointer { rollBack(current) }
    }

    private func rollBack(_ bad: Pointer) {
        try? FileManager.default.removeItem(at: directory(bad.version))
        if let previous = bad.previous, let feed = bad.previousFeedVersion {
            try? save(Pointer(version: previous, feedVersion: feed, confirmed: true))
        } else {
            try? save(nil)
        }
    }

    /// Adds a verified set; it counts from the next launch. Keeps the set in use until then, removes older ones.
    func install(version: Int, feedVersion: String, files: [String: Data]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appending(path: "incoming-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for (path, data) in files {
            let file = temporary.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = temporary
        try marked.setResourceValues(values)
        let target = directory(version)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)

        let old = pointer
        // An unstarted set isn't a safe place to go back to.
        let keep = old?.confirmed == true ? old : nil
        try save(Pointer(version: version, feedVersion: feedVersion, confirmed: false, previous: keep?.version ?? old?.previous,
                         previousFeedVersion: keep?.feedVersion ?? old?.previousFeedVersion))
        let wanted = Set([version, keep?.version ?? old?.previous].compactMap { $0 }.map { "v\($0)" })
        let present = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in present where name.hasPrefix("v") && !wanted.contains(name) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }
}
