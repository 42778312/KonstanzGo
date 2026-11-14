import Foundation
import KGLiveAPI
import Logging

/// Writes what the source says into the store: shared by the poller and the stop-departures endpoint.
public struct Recorder: Sendable {
    let matcher: TripMatcher
    let timetable: Timetable
    let store: LiveStore

    public init(timetable: Timetable, store: LiveStore) {
        self.timetable = timetable
        matcher = TripMatcher(timetable: timetable)
        self.store = store
    }

    public struct Tally: Sendable {
        public var city = 0
        public var matched = 0
        public var live = 0
    }

    /// Matches each departure and records the monitored ones. Returns how many city departures matched.
    @discardableResult
    public func record(_ departures: [UpstreamDeparture], at now: Date) async -> Tally {
        var tally = Tally()
        for departure in departures where matcher.isCity(departure) {
            tally.city += 1
            guard let match = matcher.match(departure) else { continue }
            tally.matched += 1
            let ends = timetable.end(of: match.trip, on: match.day)
            if departure.isCancelled {
                await store.record(match.key, TripLive(delay: 0, observedAt: now, isCancelled: true, endsAt: ends))
            } else if let delay = departure.delay {
                tally.live += 1
                await store.record(match.key, TripLive(delay: delay, observedAt: now, isCancelled: false, endsAt: ends))
            }
        }
        return tally
    }
}

/// The hub sweep: every `interval` seconds, asks each hub stop once, one at a time with a small random gap,
/// through the guarded source; then rebuilds the snapshot. Skips cycles when no city bus runs in the next 20 min.
public actor PollScheduler {
    let timetable: Timetable
    let hubs: [Timetable.Station]
    let source: GuardedSource
    let recorder: Recorder
    let store: LiveStore
    let snapshot: SnapshotCache
    let metrics: Metrics
    let clock: any LiveClock
    let interval: Double
    let isEnabled: Bool
    let logger: Logger
    let gap: @Sendable () -> Double
    private var stopRequested = false
    private var running = false

    public init(timetable: Timetable, hubs: [Timetable.Station], source: GuardedSource, store: LiveStore,
                snapshot: SnapshotCache, metrics: Metrics, clock: any LiveClock = SystemClock(), interval: Double = 30,
                isEnabled: Bool = true, logger: Logger = Logger(label: "live.poller"),
                gap: @escaping @Sendable () -> Double = { Double.random(in: 0.1...0.4) }) {
        self.timetable = timetable
        self.hubs = hubs
        self.source = source
        recorder = Recorder(timetable: timetable, store: store)
        self.store = store
        self.snapshot = snapshot
        self.metrics = metrics
        self.clock = clock
        self.interval = interval
        self.isEnabled = isEnabled
        self.logger = logger
        self.gap = gap
    }

    /// Runs until `stop()`. The request in flight finishes first.
    public func run() async {
        running = true
        defer { running = false }
        logger.info("poller started", metadata: ["hubs": "\(hubs.map(\.gid))", "interval": "\(interval)"])
        while !stopRequested {
            let started = clock.now()
            await cycle()
            // Sleep in short slices, so a stop is noticed quickly.
            while !stopRequested, clock.now().timeIntervalSince(started) < interval {
                try? await clock.sleep(seconds: min(0.5, interval - clock.now().timeIntervalSince(started)))
            }
        }
        logger.info("poller stopped")
    }

    public func stop() { stopRequested = true }

    public var isRunning: Bool { running }

    /// One sweep. Returns the upstream state it reported.
    @discardableResult
    public func cycle() async -> UpstreamState {
        let now = clock.now()
        guard isEnabled else {
            await snapshot.rebuild(from: store, upstream: .off, at: now)
            return .off
        }
        let running = timetable.runningCityTrips(at: now, ahead: 20)
        guard !running.isEmpty else {
            await metrics.count("poll_cycles_total", label: "quiet")
            await store.prune(at: now)
            await snapshot.rebuild(from: store, upstream: .ok, at: now)
            return .ok
        }
        var successes = 0
        var total = Recorder.Tally()
        for (index, hub) in hubs.enumerated() {
            if stopRequested { break }
            if index > 0 { try? await clock.sleep(seconds: gap()) }
            do {
                let departures = try await source.departures(stopGID: hub.gid, limit: 40)
                successes += 1
                let tally = await recorder.record(departures, at: clock.now())
                total.city += tally.city
                total.matched += tally.matched
                total.live += tally.live
                await metrics.count("live_departures_total", label: "matched", by: tally.matched)
                await metrics.count("live_unmatched_total", by: tally.city - tally.matched)
            } catch let error as UpstreamError {
                logger.warning("upstream failed", metadata: ["stop": "\(hub.gid)", "error": "\(error)"])
                if error == .circuitOpen { break }
            } catch {
                logger.warning("upstream failed", metadata: ["stop": "\(hub.gid)", "error": "\(error)"])
            }
        }
        let end = clock.now()
        let circuit = await source.circuitState()
        let state: UpstreamState = successes > 0 && circuit == .closed ? .ok : .degraded
        await metrics.set("circuit_state", circuit == .closed ? 0 : circuit == .halfOpen ? 1 : 2)
        if successes > 0 { await snapshot.markSuccess(at: end) }
        await store.prune(at: end)
        await snapshot.rebuild(from: store, upstream: state, at: end)
        await metrics.count("poll_cycles_total", label: state.rawValue)
        if total.city > 0 { await metrics.set("live_match_rate", Double(total.matched) / Double(total.city)) }
        let fresh = await store.fresh(at: end)
        let runningKeys = Set(running.map { $0.trip.key(on: $0.day) })
        await metrics.set("live_trip_coverage", Double(runningKeys.filter { fresh[$0] != nil }.count)
            / Double(max(runningKeys.count, 1)))
        await metrics.set("live_trips", Double(fresh.count))
        return state
    }
}
