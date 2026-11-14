import AsyncHTTPClient
import KGLiveAPI
import LiveCore
import NIOConcurrencyHelpers
import Vapor

/// Everything the routes and the lifecycle share, built once at boot.
public struct LiveServices: Sendable {
    public let config: LiveConfig
    public let timetable: Timetable
    public let snapshot: SnapshotCache
    public let stops: StopDepartures
    public let poller: PollScheduler
    public let metrics: Metrics
    public let source: GuardedSource
}

private struct LiveServicesKey: StorageKey {
    typealias Value = LiveServices
}

extension Application {
    public var live: LiveServices {
        get {
            guard let services = storage[LiveServicesKey.self] else { fatalError("configure(_:) has not run") }
            return services
        }
        set { storage[LiveServicesKey.self] = newValue }
    }
}

/// Builds the server: loads the timetable, picks the hubs, wires the guarded source, and registers the routes.
public func configure(_ app: Application, config: LiveConfig = LiveConfig()) async throws {
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = config.port
    // Bodies are gzipped once when the snapshot is built; never compress again per request.
    app.http.server.configuration.responseCompression = .disabled
    app.http.client.configuration.decompression = .enabled(limit: .ratio(40))
    app.http.client.configuration.timeout = .init(connect: .seconds(5), read: .seconds(5))

    let started = Date()
    let timetable = try Timetable(path: config.timetablePath)
    let (today, _) = BerlinTime.wallClock(of: started)
    app.logger.info("timetable loaded", metadata: [
        "feed": "\(timetable.feedVersion)", "valid": "\(timetable.feedStart)-\(timetable.feedEnd)",
        "stations": "\(timetable.stations.count)", "trips": "\(timetable.trips.count)",
        "stopTimes": "\(timetable.stopTimeCount)", "ms": "\(Int(Date().timeIntervalSince(started) * 1000))",
    ])
    if today > timetable.feedEnd || today < timetable.feedStart {
        app.logger.error("the timetable does not cover today; no trips will match", metadata: ["today": "\(today)"])
    }

    let hubs: [Timetable.Station]
    if config.hubStops.isEmpty {
        let computed = timetable.hubs()
        hubs = computed.stations
        app.logger.info("hub stops computed", metadata: [
            "count": "\(hubs.count)", "coverage": "\(Int(computed.coverage * 100))%",
            "stops": "\(hubs.map { "\($0.name) \($0.gid)" })",
        ])
    } else {
        hubs = config.hubStops.compactMap { gid in timetable.stations(forGID: gid).first.flatMap { timetable.stations[$0] } }
        app.logger.info("hub stops from HUB_STOPS", metadata: ["count": "\(hubs.count)"])
    }

    let metrics = Metrics()
    let store = LiveStore()
    let source = GuardedSource(
        source: EFAClient(http: app.http.client.shared, userAgent: config.userAgent),
        limiter: RateLimiter(rate: config.upstreamMaxRPS, burst: 2),
        breaker: CircuitBreaker(),
        metrics: metrics,
        isEnabled: config.upstreamEnabled
    )
    let state: UpstreamState = config.upstreamEnabled ? .degraded : .off
    let snapshot = SnapshotCache(now: Date(), upstream: state)
    var pollLogger = app.logger
    pollLogger[metadataKey: "component"] = "poller"
    let poller = PollScheduler(timetable: timetable, hubs: hubs, source: source, store: store, snapshot: snapshot,
                               metrics: metrics, interval: config.pollIntervalSeconds,
                               isEnabled: config.upstreamEnabled, logger: pollLogger)
    let stops = StopDepartures(timetable: timetable, source: source, store: store, isEnabled: config.upstreamEnabled,
                               logger: app.logger)
    app.live = LiveServices(config: config, timetable: timetable, snapshot: snapshot, stops: stops, poller: poller,
                            metrics: metrics, source: source)
    app.lifecycle.use(PollerLifecycle(poller: poller))
    try routes(app)
}

/// Starts the poller when the server boots and stops it on shutdown, after the request in flight.
final class PollerLifecycle: LifecycleHandler, @unchecked Sendable {
    let poller: PollScheduler
    private let lock = NIOLock()
    private var task: Task<Void, Never>?

    init(poller: PollScheduler) {
        self.poller = poller
    }

    func didBootAsync(_ application: Application) async throws {
        let poller = poller
        lock.withLock { task = Task { await poller.run() } }
    }

    func shutdownAsync(_ application: Application) async {
        await poller.stop()
        let running = lock.withLock { task }
        await running?.value
        application.logger.info("poller finished, shutting down")
    }
}
