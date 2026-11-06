import CryptoKit
import Foundation
import GRDB

/// Where updated data comes from. Nil until the owner has chosen a host (plan task P1-14): the app then simply
/// stays on the data it shipped with.
public enum DataHost {
    public static let base: URL? = nil
    /// Public Ed25519 keys, base64: the one in use and a spare for rotating. `DataPipeline/publish.py keygen`.
    public static let trustedKeys = [
        "ZEpL0oUkwz9e1ECOBikpdvyUI/yn92U/Ji+O9HFSmZs=",
        "KHb/UG6J5ByYY9e3TfUTJxyRk0O4V7oWqooozCsGq0k="
    ]
}

/// A published data set: `manifest.json`, signed in `manifest.sig` (`DataPipeline/publish.py`).
struct DataManifest: Codable, Equatable {
    struct File: Codable, Equatable {
        /// Where it goes in the data folder, such as "timetable.db".
        var path: String
        /// The gzip file, relative to the host.
        var url: String
        /// SHA-256 of the unpacked file, in hex.
        var sha256: String
    }

    var version: Int
    var feedVersion: String
    var schema: Int
    var minAppBuild: Int
    var files: [File]
}

public enum DataSyncOutcome: Sendable, Equatable {
    /// No host chosen yet.
    case noHost
    /// Checked less than a day ago, or a check is already running.
    case notDue
    case upToDate
    /// Counts from the next launch.
    case installed(version: Int)
    case failed
}

/// Keeps the offline data fresh without an app release: at most once a day, one check at a time, and nothing
/// replaces good data until its signature, hashes and contents have all been checked. Any failure leaves the
/// data in use untouched.
public actor DataSync {
    /// The schema of `timetable.db` this build reads.
    static let timetableSchema = 4
    static let interval: TimeInterval = 24 * 3600
    static let allowedPaths: Set<String> = ["timetable.db", "search/places.tsvz", "walk/konstanz-walk.bin"]

    /// Reads a URL. With a tag it may answer nil for "not changed"; also returns the new tag.
    public typealias Fetch = @Sendable (URL, String?) async throws -> (data: Data?, tag: String?)

    private let base: URL?
    private let store: DataStore
    private let keys: [Curve25519.Signing.PublicKey]
    private let fetch: Fetch
    private let defaults: UserDefaults
    private let appBuild: Int
    private let bundledFeed: String
    private var running = false

    public init(base: URL? = DataHost.base, store: DataStore = .shared, keys: [String] = DataHost.trustedKeys,
                fetch: @escaping Fetch = DataSync.download, defaults: UserDefaults = .standard,
                appBuild: Int, bundledFeed: String) {
        self.base = base
        self.store = store
        self.keys = keys.compactMap { Data(base64Encoded: $0) }.compactMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
        self.fetch = fetch
        self.defaults = defaults
        self.appBuild = appBuild
        self.bundledFeed = bundledFeed
    }

    public nonisolated var hasHost: Bool { base != nil }

    // What `refreshConfig` needs from here.
    var hostForConfig: URL? { base }
    var lastConfigCheck: Date? { defaults.object(forKey: "config.lastCheck") as? Date }
    func fetchForConfig(_ url: URL, _ tag: String?) async throws -> (data: Data?, tag: String?) { try await fetch(url, tag) }
    func isSignedForConfig(_ data: Data, signature: Data) -> Bool { Self.isSigned(data, signature: signature, by: keys) }
    func noteConfigCheck(_ date: Date) { defaults.set(date, forKey: "config.lastCheck") }
    func storeConfig(_ bytes: Data) throws {
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try bytes.write(to: store.folder.appending(path: "config.json"), options: .atomic)
    }

    /// Checks for new data if it's due, or now when `force` is set.
    public func refresh(now: Date = .now, force: Bool = false) async -> DataSyncOutcome {
        guard let base else { return .noHost }
        guard !running else { return .notDue }
        if !force, let last = defaults.object(forKey: "data.lastCheck") as? Date, now.timeIntervalSince(last) < Self.interval {
            return .notDue
        }
        running = true
        defer { running = false }
        do {
            let outcome = try await check(base: base, now: now)
            defaults.set(now, forKey: "data.lastCheck")  // A failure stays due.
            return outcome
        } catch {
            return .failed
        }
    }

    private func check(base: URL, now: Date) async throws -> DataSyncOutcome {
        let manifestURL = base.appending(path: "manifest.json")
        let tag = store.currentVersion == nil ? nil : defaults.string(forKey: "data.manifestTag")
        let answer = try await fetch(manifestURL, tag)
        guard let bytes = answer.data else { return .upToDate }
        guard let signature = try await fetch(base.appending(path: "manifest.sig"), nil).data,
              Self.isSigned(bytes, signature: signature, by: keys) else { throw Failure.badSignature }
        let manifest = try JSONDecoder().decode(DataManifest.self, from: bytes)
        // Same or older than what's here; another build's schema; a newer app needed: wait for an app update.
        guard manifest.version > store.currentVersion ?? 0, manifest.feedVersion >= bundledFeed,
              manifest.schema == Self.timetableSchema, manifest.minAppBuild <= appBuild else {
            defaults.set(answer.tag, forKey: "data.manifestTag")
            return .upToDate
        }
        var files: [String: Data] = [:]
        for file in manifest.files {
            guard Self.allowedPaths.contains(file.path) else { throw Failure.badFile }
            guard let packed = try await fetch(base.appending(path: file.url), nil).data else { throw Failure.badFile }
            let data = try Gzip.decompress(packed)
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw Failure.badFile }
            files[file.path] = data
        }
        if let timetable = files["timetable.db"] {
            try Self.checkTimetable(timetable, schema: manifest.schema, now: now)
        }
        try store.install(version: manifest.version, feedVersion: manifest.feedVersion, files: files)
        defaults.set(answer.tag, forKey: "data.manifestTag")
        return .installed(version: manifest.version)
    }

    static func isSigned(_ data: Data, signature: Data, by keys: [Curve25519.Signing.PublicKey]) -> Bool {
        keys.contains { $0.isValidSignature(signature, for: data) }
    }

    /// Opens the new timetable before anything relies on it: whole, the right schema, not empty, not over.
    static func checkTimetable(_ data: Data, schema: Int, now: Date) throws {
        let file = URL.temporaryDirectory.appending(path: "check-\(UUID().uuidString).db")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var configuration = Configuration()
        configuration.readonly = true
        let (version, integrity) = try DatabaseQueue(path: file.path, configuration: configuration).read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0, try String.fetchOne(db, sql: "PRAGMA integrity_check"))
        }
        guard version == schema, integrity == "ok" else { throw Failure.badTimetable }
        let info = try TimetableInfo.read(from: file)
        guard info.stations > 0, info.trips > 0, let until = Calendar.konstanz.date(from: info.validUntil),
              Calendar.konstanz.startOfDay(for: now) <= until else { throw Failure.badTimetable }
    }

    enum Failure: Error { case badSignature, badFile, badTimetable }

    public nonisolated static func download(_ url: URL, tag: String?) async throws -> (data: Data?, tag: String?) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("KonstanzGo (iOS; konstant@werkflow.cc)", forHTTPHeaderField: "User-Agent")
        if let tag { request.setValue(tag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return (data, nil) }  // a file: address, for testing
        if http.statusCode == 304 { return (nil, tag) }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return (data, http.value(forHTTPHeaderField: "ETag"))
    }
}
