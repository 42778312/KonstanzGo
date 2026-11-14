import Foundation
import KGLiveAPI
import Logging

/// Live departures for one stop sheet, on demand. Answers from a 20 s cache per stop; on a miss, at most one
/// request per stop is in flight and everyone else waits for it. When the source can't be asked, it answers from
/// the cache or the timetable with `upstream: degraded`, never with an error.
public actor StopDepartures {
    static let fetchLimit = 20
    public static let maxLimit = 20

    struct Entry {
        let departures: [DepartureDTO]
        let upstream: UpstreamState
        let at: Date
    }

    let timetable: Timetable
    let source: GuardedSource
    let recorder: Recorder
    let matcher: TripMatcher
    let clock: any LiveClock
    let ttl: TimeInterval
    let isEnabled: Bool
    let logger: Logger
    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<Entry, Never>] = [:]

    public init(timetable: Timetable, source: GuardedSource, store: LiveStore, clock: any LiveClock = SystemClock(),
                ttl: TimeInterval = 20, isEnabled: Bool = true, logger: Logger = Logger(label: "live.stops")) {
        self.timetable = timetable
        self.source = source
        recorder = Recorder(timetable: timetable, store: store)
        matcher = TripMatcher(timetable: timetable)
        self.clock = clock
        self.ttl = ttl
        self.isEnabled = isEnabled
        self.logger = logger
    }

    /// Nil for a stop the timetable doesn't know.
    public func departures(gid: String, limit: Int) async -> StopDeparturesDTO? {
        guard TripKey.isStopGID(gid), !timetable.stations(forGID: gid).isEmpty else { return nil }
        let now = clock.now()
        let entry: Entry
        if let cached = cache[gid], now.timeIntervalSince(cached.at) < ttl {
            entry = cached
        } else if let task = inFlight[gid] {
            entry = await task.value
        } else {
            let task = Task { await self.fetch(gid: gid) }
            inFlight[gid] = task
            entry = await task.value
            inFlight[gid] = nil
        }
        let shown = entry.departures.filter { ($0.realtime ?? $0.planned) >= Int(now.timeIntervalSince1970) - 60 }
        return StopDeparturesDTO(generatedAt: Int(entry.at.timeIntervalSince1970), upstream: entry.upstream, stop: gid,
                                 departures: Array(shown.prefix(max(1, min(limit, Self.maxLimit)))))
    }

    private func fetch(gid: String) async -> Entry {
        do {
            let found = try await source.departures(stopGID: gid, limit: Self.fetchLimit)
            let now = clock.now()
            await recorder.record(found, at: now)
            let entry = Entry(departures: found.map(dto), upstream: .ok, at: now)
            cache[gid] = entry
            return entry
        } catch {
            if (error as? UpstreamError) != .disabled {
                logger.info("stop departures from fallback", metadata: ["stop": "\(gid)", "error": "\(error)"])
            }
            let now = clock.now()
            let state: UpstreamState = isEnabled ? .degraded : .off
            if let cached = cache[gid], now.timeIntervalSince(cached.at) < 120 {
                return Entry(departures: cached.departures, upstream: state, at: cached.at)
            }
            let planned = timetable.scheduledDepartures(gid: gid, from: now.addingTimeInterval(-60), limit: Self.fetchLimit)
                .map { item in
                    DepartureDTO(k: item.trip.key(on: item.day), line: item.trip.line, destination: item.trip.headsign,
                                 platform: item.platform, planned: Int(item.at.timeIntervalSince1970), realtime: nil,
                                 cancelled: false)
                }
            return Entry(departures: planned, upstream: state, at: now)
        }
    }

    private func dto(_ departure: UpstreamDeparture) -> DepartureDTO {
        DepartureDTO(k: matcher.isCity(departure) ? matcher.match(departure)?.key : nil, line: departure.line,
                     destination: departure.destinationName, platform: departure.platform,
                     planned: Int(departure.planned.timeIntervalSince1970),
                     realtime: departure.realtime.map { Int($0.timeIntervalSince1970) }, cancelled: departure.isCancelled)
    }
}
