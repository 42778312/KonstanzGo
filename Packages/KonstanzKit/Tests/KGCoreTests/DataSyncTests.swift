import Compression
import CryptoKit
import Foundation
import Testing
@testable import KGCore

/// A pretend host: files by name, a call log, and an optional ETag.
final class FakeHost: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private(set) var asked: [String] = []
    var tag: String?

    subscript(name: String) -> Data? {
        get { lock.withLock { files[name] } }
        set { lock.withLock { files[name] = newValue } }
    }

    func fetch(_ url: URL, _ sentTag: String?) throws -> (data: Data?, tag: String?) {
        lock.lock(); defer { lock.unlock() }
        let name = url.path.split(separator: "/").joined(separator: "/")
        asked.append(name)
        if let tag, sentTag == tag { return (nil, tag) }
        guard let data = files[name] else { throw URLError(.fileDoesNotExist) }
        return (data, tag)
    }
}

/// A gzip file around Apple's raw DEFLATE: the header, the stream, and a trailer with the size (`Gzip` reads no checksum).
private func gzipped(_ data: Data) throws -> Data {
    let source = [UInt8](data)
    var deflated = [UInt8](repeating: 0, count: source.count + 1_024)
    let written = compression_encode_buffer(&deflated, deflated.count, source, source.count, nil, COMPRESSION_ZLIB)
    let size = UInt32(source.count)
    let trailer = [0, 0, 0, 0, UInt8(size & 255), UInt8(size >> 8 & 255), UInt8(size >> 16 & 255), UInt8(size >> 24 & 255)]
    return Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255] + deflated.prefix(written) + trailer)
}

@Suite("Data updates", .serialized)
struct DataSyncTests {
    static let now = Date(timeIntervalSince1970: 1_793_000_000)  // Nov 2026, while the shipped timetable is valid
    let key = Curve25519.Signing.PrivateKey()
    let host = FakeHost()
    let store = DataStore(folder: URL.temporaryDirectory.appending(path: "store-\(UUID().uuidString)"))
    let suite = "sync-\(UUID().uuidString)"
    let timetable = try! Data(contentsOf: repoData.timetable)  // swiftlint:disable:this force_try

    private func sync(keys: [String]? = nil, build: Int = 10, feed: String = "20261011") -> DataSync {
        let host = host
        return DataSync(base: URL(string: "https://example.test/")!, store: store,
                        keys: keys ?? [key.publicKey.rawRepresentation.base64EncodedString()],
                        fetch: { url, tag in try host.fetch(url, tag) }, defaults: UserDefaults(suiteName: suite)!, appBuild: build, bundledFeed: feed)
    }

    private func publish(version: Int = 100, content: Data? = nil, hash: Data? = nil, feed: String = "20261011",
                         schema: Int = 4, minBuild: Int = 0, path: String = "timetable.db") throws {
        let data = content ?? timetable
        host["\(version)/t.gz"] = try gzipped(data)
        let sha = SHA256.hash(data: hash ?? data).map { String(format: "%02x", $0) }.joined()
        let manifest = DataManifest(version: version, feedVersion: feed, schema: schema, minAppBuild: minBuild,
                                    files: [.init(path: path, url: "\(version)/t.gz", sha256: sha)])
        let bytes = try JSONEncoder().encode(manifest)
        host["manifest.json"] = bytes
        host["manifest.sig"] = try key.signature(for: bytes)
    }

    @Test func noHostDoesNothing() async {
        let sync = DataSync(base: nil, store: store, fetch: { _, _ in throw URLError(.badURL) }, defaults: UserDefaults(suiteName: suite)!,
                            appBuild: 1, bundledFeed: "x")
        #expect(await sync.refresh(now: Self.now) == .noHost)
        #expect(!sync.hasHost)
    }

    @Test func aGoodSetInstallsAndCountsFromTheNextLaunch() async throws {
        try publish()
        #expect(await sync().refresh(now: Self.now) == .installed(version: 100))
        #expect(store.currentVersion == 100)
        let overlay = try #require(store.overlayForLaunch(bundledFeed: "20261011"))
        #expect(try Data(contentsOf: overlay.appending(path: "timetable.db")) == timetable)
        let data = BundledData(root: repoData.root, overlay: overlay)
        #expect(data.timetable.path.hasPrefix(overlay.path))
        #expect(data.mapStyle.path.hasPrefix(repoData.root.path), "the map stays in the app")
        #expect(data.bundled.timetable.path.hasPrefix(repoData.root.path))
    }

    @Test func aTamperedFileIsRefused() async throws {
        try publish(content: timetable, hash: Data("something else".utf8))
        #expect(await sync().refresh(now: Self.now) == .failed)
        #expect(store.currentVersion == nil)
    }

    @Test func aForgedManifestIsRefused() async throws {
        try publish()
        host["manifest.sig"] = try Curve25519.Signing.PrivateKey().signature(for: host["manifest.json"]!)
        #expect(await sync().refresh(now: Self.now) == .failed)
        #expect(store.currentVersion == nil)
    }

    @Test func aChangedManifestIsRefused() async throws {
        try publish()
        host["manifest.json"] = host["manifest.json"]! + Data(" ".utf8)
        #expect(await sync().refresh(now: Self.now) == .failed)
    }

    @Test func aDamagedOrEndedTimetableIsRefused() async throws {
        try publish(content: Data(repeating: 7, count: 8_192))
        #expect(await sync().refresh(now: Self.now) == .failed)
        try publish()
        let afterTheEnd = Date(timeIntervalSince1970: 1_830_000_000)
        #expect(await sync().refresh(now: afterTheEnd) == .failed)
        #expect(store.currentVersion == nil)
    }

    @Test func aFileOutsideTheDataFolderIsRefused() async throws {
        try publish(path: "../../evil.db")
        #expect(await sync().refresh(now: Self.now) == .failed)
    }

    @Test func otherSchemasNewerAppsAndOlderFeedsWait() async throws {
        try publish(schema: 5)
        #expect(await sync().refresh(now: Self.now, force: true) == .upToDate)
        try publish(minBuild: 99)
        #expect(await sync().refresh(now: Self.now, force: true) == .upToDate)
        try publish(feed: "20260101")
        #expect(await sync().refresh(now: Self.now, force: true) == .upToDate)
        #expect(store.currentVersion == nil)
    }

    @Test func checksAtMostOnceADayUnlessForced() async throws {
        try publish()
        let sync = sync()
        _ = await sync.refresh(now: Self.now)
        let count = host.asked.count
        #expect(await sync.refresh(now: Self.now.addingTimeInterval(23 * 3600)) == .notDue)
        #expect(host.asked.count == count)
        #expect(await sync.refresh(now: Self.now.addingTimeInterval(23 * 3600), force: true) == .upToDate)
        #expect(host.asked.count > count)
    }

    @Test func aFailureStaysDue() async throws {
        let sync = sync()
        #expect(await sync.refresh(now: Self.now) == .failed)
        try publish()
        #expect(await sync.refresh(now: Self.now.addingTimeInterval(60)) == .installed(version: 100))
    }

    @Test func anUnchangedManifestDownloadsNothingMore() async throws {
        try publish()
        host.tag = "one"
        let sync = sync()
        _ = await sync.refresh(now: Self.now)
        let count = host.asked.count
        #expect(await sync.refresh(now: Self.now, force: true) == .upToDate)
        #expect(host.asked.count == count + 1)
    }

    @Test func aSetThatFailsToStartIsDroppedOnTheNextLaunch() async throws {
        try publish()
        _ = await sync().refresh(now: Self.now)
        #expect(store.overlayForLaunch(bundledFeed: "20261011") != nil)  // tried, never confirmed
        #expect(store.overlayForLaunch(bundledFeed: "20261011") == nil)
        #expect(store.currentVersion == nil)
    }

    @Test func aFailedNewSetGoesBackToTheLastGoodOne() async throws {
        try publish(version: 100)
        _ = await sync().refresh(now: Self.now)
        #expect(store.overlayForLaunch(bundledFeed: "20261011") != nil)
        store.confirm()
        try publish(version: 200)
        _ = await sync().refresh(now: Self.now, force: true)
        #expect(store.currentVersion == 200)
        #expect(store.overlayForReading(bundledFeed: "20261011")?.lastPathComponent == "v100", "widgets stay on the good set")
        #expect(store.overlayForLaunch(bundledFeed: "20261011")?.lastPathComponent == "v200")
        #expect(store.overlayForLaunch(bundledFeed: "20261011")?.lastPathComponent == "v100")
        #expect(store.currentVersion == 100)
    }

    @Test func anAppUpdateWithNewerDataWins() async throws {
        try publish()
        _ = await sync().refresh(now: Self.now)
        store.confirm()
        #expect(store.overlayForLaunch(bundledFeed: "20270101") == nil)
    }

    @Test func oldSetsAreRemoved() async throws {
        for version in [100, 200, 300] {
            try publish(version: version)
            _ = await sync().refresh(now: Self.now, force: true)
            _ = store.overlayForLaunch(bundledFeed: "20261011")
            store.confirm()
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: store.folder.path).filter { $0.hasPrefix("v") }
        #expect(Set(names) == ["v200", "v300"])
    }

    // MARK: Settings

    @Test func settingsNeedASignatureAndStayWithinLimits() async throws {
        let bytes = Data(#"{"liveEnabled":false,"stopReadSeconds":1,"bannerID":"a","bannerDE":"Hallo"}"#.utf8)
        host["config.json"] = bytes
        host["config.sig"] = try Curve25519.Signing.PrivateKey().signature(for: bytes)
        #expect(await sync().refreshConfig(now: Self.now) == nil, "forged")
        #expect(RemoteConfig.cached(in: store) == .standard)
        host["config.sig"] = try key.signature(for: bytes)
        let config = try #require(await sync().refreshConfig(now: Self.now))
        #expect(!config.liveEnabled)
        #expect(config.stopReadSeconds == 15, "held to the limit")
        #expect(RemoteConfig.cached(in: store) == config)
        #expect(await sync().refreshConfig(now: Self.now.addingTimeInterval(60)) == nil, "not due yet")
    }

    @Test func unknownOrMissingSettingsKeepDefaults() throws {
        let config = try JSONDecoder().decode(RemoteConfig.self, from: Data(#"{"somethingNew":1}"#.utf8))
        #expect(config == .standard)
    }

    @Test func aManifestFromThePipelineVerifies() throws {
        // Run after `publish.py data` with KONSTANZGO_PUBLISH_DIR and DataHost's keys: Python signs, Swift checks.
        guard let folder = ProcessInfo.processInfo.environment["KG_PUBLISHED"].map({ URL(filePath: $0) }) else { return }
        let bytes = try Data(contentsOf: folder.appending(path: "manifest.json"))
        let signature = try Data(contentsOf: folder.appending(path: "manifest.sig"))
        let keys = DataHost.trustedKeys.compactMap { Data(base64Encoded: $0) }
            .compactMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
        #expect(keys.count == 2)
        #expect(DataSync.isSigned(bytes, signature: signature, by: keys))
        let manifest = try JSONDecoder().decode(DataManifest.self, from: bytes)
        #expect(manifest.schema == DataSync.timetableSchema)
        let file = try #require(manifest.files.first { $0.path == "timetable.db" })
        let data = try Gzip.decompress(Data(contentsOf: folder.appending(path: file.url)))
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == file.sha256)
    }
}
