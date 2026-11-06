import Foundation
import Network
import Observation

/// What's really happening on the road, from EFA-BW: disruptions, kept on the phone and refreshed the moment
/// it has internet, and delays, which are only trusted for a few minutes. Offline the app runs on the last
/// disruptions it knows, each ending by itself at its own end time, and on plain timetable times.
@MainActor
@Observable
public final class LiveModel {
    public private(set) var notices: [ServiceNotice]
    /// When the disruptions were last read from the source.
    public private(set) var updated: Date?
    public private(set) var isOnline = true
    /// Moves on every half minute, so notices that have ended disappear without a restart.
    public private(set) var now = Date.now
    /// Per trip, what the last report said: seconds late, for the buses on the map.
    public private(set) var tripDelays: [Int: Double] = [:]
    public private(set) var cancelledTrips: Set<Int> = []

    public typealias Fetch = @Sendable (URL) async throws -> Data

    private struct Saved: Codable {
        var notices: [ServiceNotice]
        var updated: Date
    }

    private let store: TimetableStore
    private let file: URL
    private let fetch: Fetch
    private let onChange: @Sendable ([ServiceNotice]) -> Void
    private var lastAsked = Date.distantPast
    private var failures = 0
    private var refreshing = false
    private var monitor: NWPathMonitor?
    private var boards: [Int: (at: Date, events: [LiveEvent])] = [:]
    private var delaySeen: [Int: Date] = [:]
    private var reading: [Int: Task<[LiveEvent]?, Never>] = [:]
    private let delayFile: URL
    private var delaysSaved = Date.distantPast
    /// Disruptions change rarely: every 5 minutes, and right away when the internet comes back.
    static let interval: TimeInterval = 5 * 60
    /// A delay this old says nothing any more: the bus goes back to its timetable position.
    static let delayLife: TimeInterval = 10 * 60
    static let boardLife: TimeInterval = 30
    /// What's shown at once without asking: a report from the last few minutes still says how late that bus is.
    static let instantLife: TimeInterval = 5 * 60

    private struct SavedDelays: Codable {
        var at: Date
        var delays: [Int: Double]
        var cancelled: Set<Int>
    }

    public init(store: TimetableStore,
                file: URL = URL.applicationSupportDirectory.appending(path: "live-notices.json"),
                fetch: @escaping Fetch = LiveModel.download,
                onChange: @escaping @Sendable ([ServiceNotice]) -> Void = { _ in }) {
        self.store = store
        self.file = file
        delayFile = file.deletingLastPathComponent().appending(path: file.deletingPathExtension().lastPathComponent + "-delays.json")
        self.fetch = fetch
        self.onChange = onChange
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        notices = saved?.notices ?? []
        updated = saved?.updated
        onChange(notices)
        restoreDelays()
    }

    // MARK: Disruptions

    public var active: [ServiceNotice] { notices.filter { $0.isActive(at: now) } }
    public var closures: StopClosures { StopClosures(notices: notices, at: now) }

    /// The active notices about a stop.
    public func notices(forStation id: Int) -> [ServiceNotice] {
        active.filter { $0.stations.contains(id) }
    }

    /// Reads the disruptions unless that happened just now. Offline or on a bad answer the kept ones stay.
    public func refresh(at date: Date = .now, force: Bool = false) async {
        guard !refreshing else { return }
        let wait = failures == 0 ? Self.interval : min(60 * pow(2, Double(failures - 1)), 15 * 60)
        guard force || date.timeIntervalSince(lastAsked) >= wait else { return }
        refreshing = true
        defer { refreshing = false }
        lastAsked = date
        do {
            let data = try await fetch(EFANotices.url)
            notices = try EFANotices.parse(data, store: store)
            updated = date
            failures = 0
            onChange(notices)
            save()
        } catch {
            failures += 1
        }
    }

    /// While the map is open: follows the clock and the internet coming back.
    public func keepFresh() async {
        startWatchingNetwork()
        while !Task.isCancelled {
            now = .now
            pruneDelays()
            await refresh()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func startWatchingNetwork() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "de.konstanzgo.live.network"))
    }

    private func networkChanged(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        guard cameBack else { return }
        failures = 0
        Task { await refresh(force: true) }
    }

    private func save() {
        guard let updated, let data = try? JSONEncoder().encode(Saved(notices: notices, updated: updated)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    // MARK: Delays

    /// Departures with what's already known, without asking anyone: for the first frame of a list, so the real
    /// time is there at once. Asking for fresher reports (`live`) follows.
    public func instant(_ departures: [Departure], at date: Date = .now) -> [Departure] {
        departures.map { departure in
            var shown = departure
            if departure.status != .stopClosed { shown.status = status(ofTrip: departure.tripID, at: date) }
            return shown
        }
    }

    /// What's known about a trip, if it was reported recently.
    public func status(ofTrip trip: Int, at date: Date = .now) -> DepartureStatus {
        guard let seen = delaySeen[trip], date.timeIntervalSince(seen) < Self.instantLife else { return .scheduled }
        if cancelledTrips.contains(trip) { return .cancelled }
        return tripDelays[trip].map { .live(delayMinutes: max(0, Int(($0 / 60).rounded()))) } ?? .scheduled
    }

    /// Reads these stops ahead of time, together, so opening one of them finds its buses already known.
    public func warm(stations: [Int], at date: Date = .now) async {
        let store = store
        let reads = Set(stations).map { station in
            Task {
                let departures = await Task.detached(priority: .utility) {
                    (try? store.departures(at: station, from: date, limit: 60, within: 2)) ?? []
                }.value
                _ = await live(departures, atStation: station, at: date)
            }
        }
        for read in reads { await read.value }
    }

    /// What's known right now, for checking a journey.
    public var state: LiveState { LiveState(delays: tripDelays, cancelled: cancelledTrips, closures: closures) }

    /// Reads the stops where the journey's next rides can be seen: where the user boards, or the next stop of
    /// the bus they're on.
    public func follow(_ journey: Journey, at date: Date = .now) async {
        now = date
        pruneDelays(at: date)
        let store = store
        for ride in journey.rides.filter({ $0.end.addingTimeInterval(tripDelays[$0.tripID] ?? 0) > date }).prefix(3) {
            let stop = ride.stops.dropLast().first { $0.departure.addingTimeInterval(tripDelays[ride.tripID] ?? 0) > date }
                ?? ride.boarding
            let from = stop.departure.addingTimeInterval(-120)
            let departures = await Task.detached(priority: .utility) {
                (try? store.departures(at: stop.station.id, from: from, limit: 40, within: 1)) ?? []
            }.value
            _ = await live(departures, atStation: stop.station.id, at: date)
        }
    }

    #if DEBUG
    /// UI tests: acts as if the operator had cancelled this trip.
    public func simulateCancelled(trip: Int) { cancelledTrips.insert(trip) }
    #endif

    /// A stop's departures with what's known right now. Asks at most every 30 s per stop; without an answer
    /// they stay plain timetable times, never an old delay.
    public func live(_ departures: [Departure], atStation id: Int, at date: Date = .now) async -> [Departure] {
        guard let events = await events(atStation: id, at: date) else { return departures }
        let merged = EFADepartures.merge(departures, with: events)
        remember(merged, at: date)
        return merged
    }

    /// Reads a busy stop for the buses on the map: most lines pass Konstanz Bahnhof.
    public func followHub(station id: Int, departures: [Departure], at date: Date = .now) async {
        _ = await live(departures, atStation: id, at: date)
    }

    private func events(atStation id: Int, at date: Date) async -> [LiveEvent]? {
        if let board = boards[id], date.timeIntervalSince(board.at) < Self.boardLife { return board.events }
        // Someone is already asking for this stop: wait for that answer.
        if let running = reading[id] { return await running.value }
        guard isOnline, let area = store.stopArea(ofStation: id), let url = EFADepartures.url(stopArea: area) else { return nil }
        let fetch = fetch
        let task = Task<[LiveEvent]?, Never> {
            guard let data = try? await fetch(url) else { return nil }
            return await Task.detached(priority: .utility) { try? EFADepartures.parse(data) }.value
        }
        reading[id] = task
        let events = await task.value
        reading[id] = nil
        if let events { boards[id] = (date, events) }
        return events
    }

    private func remember(_ departures: [Departure], at date: Date) {
        for departure in departures {
            switch departure.status {
            case let .live(minutes):
                tripDelays[departure.tripID] = departure.delaySeconds.map(Double.init) ?? Double(minutes) * 60
                delaySeen[departure.tripID] = date
            case .cancelled:
                cancelledTrips.insert(departure.tripID)
                delaySeen[departure.tripID] = date
            case .scheduled, .stopClosed:
                break
            }
        }
        saveDelays(at: date)
    }

    private func saveDelays(at date: Date) {
        guard date.timeIntervalSince(delaysSaved) > 20 else { return }
        delaysSaved = date
        let saved = SavedDelays(at: date, delays: tripDelays, cancelled: cancelledTrips)
        let file = delayFile
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(saved) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// The last reports, if the app was closed only a moment ago: the buses have the same delays still.
    private func restoreDelays(at date: Date = .now) {
        guard let data = try? Data(contentsOf: delayFile), let saved = try? JSONDecoder().decode(SavedDelays.self, from: data),
              date.timeIntervalSince(saved.at) < Self.instantLife else { return }
        tripDelays = saved.delays
        cancelledTrips = saved.cancelled
        for trip in Set(saved.delays.keys).union(saved.cancelled) { delaySeen[trip] = saved.at }
    }

    private func pruneDelays(at date: Date = .now) {
        for (trip, seen) in delaySeen where date.timeIntervalSince(seen) > Self.delayLife {
            delaySeen[trip] = nil
            tripDelays[trip] = nil
            cancelledTrips.remove(trip)
        }
    }

    public nonisolated static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("KonstanzGo (iOS; konstant@werkflow.cc)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
