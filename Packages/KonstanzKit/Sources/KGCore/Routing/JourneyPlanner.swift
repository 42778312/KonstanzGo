import Foundation
import GRDB
import Synchronization

/// Start or target of a journey.
public struct Endpoint: Sendable, Hashable {
    public var name: String
    public var coordinate: Coordinate

    public init(name: String, coordinate: Coordinate) {
        self.name = name
        self.coordinate = coordinate
    }
}

/// What the user prefers in "Wann & wie" (screen 19).
public enum RoutePreference: String, Sendable, Hashable, CaseIterable, Codable {
    case fastest, leastWalking, fewestTransfers
}

/// The label a journey gets in the list (screen 10).
public enum JourneyTag: String, Sendable, Hashable, CaseIterable {
    case fastest, leastWalking, fewestTransfers
}

public struct PlanRequest: Sendable, Hashable {
    public var from: Endpoint
    public var to: Endpoint
    /// Leave at this time, or arrive by it when `arriveBy`.
    public var time: Date
    public var arriveBy: Bool
    public var preference: RoutePreference

    public init(from: Endpoint, to: Endpoint, time: Date, arriveBy: Bool = false,
                preference: RoutePreference = .fastest) {
        self.from = from
        self.to = to
        self.time = time
        self.arriveBy = arriveBy
        self.preference = preference
    }
}

/// Plans journeys on the offline timetable. Same rules as the Android app: stations within a
/// 15-minute walk of start and target (at least the nearest two), transfers on foot between stations
/// up to 400 m apart, one minute to change at the same station, up to four bus options leaving as late as
/// possible, plus walking the whole way when that is short or about as quick.
public final class JourneyPlanner: Sendable {
    public static let maxAccessMinutes = 15
    public static let footpathMetres = 400.0
    public static let maxOptions = 4

    private let store: TimetableStore
    private let queue: DatabaseQueue
    private let clock: ServiceClock
    /// Street paths and steps for walking legs; without it walks are straight-line estimates.
    private let walker: WalkRouter?
    private let footpaths: [Int: [Access]]
    /// The scan for the most recent planning day; building it takes a few tens of ms.
    private let cache = Mutex<(day: ServiceDay, scan: ConnectionScan)?>(nil)

    public init(store: TimetableStore, url: URL, walker: WalkRouter? = nil,
                clock: ServiceClock = ServiceClock()) throws {
        self.store = store
        self.clock = clock
        self.walker = walker
        var config = Configuration()
        config.readonly = true
        queue = try DatabaseQueue(path: url.path, configuration: config)

        var paths: [Int: [Access]] = [:]
        for station in store.stations {
            paths[station.id] = store.stations.compactMap { other in
                guard station.id != other.id else { return nil }
                let metres = station.coordinate.distance(to: other.coordinate)
                guard metres <= Self.footpathMetres else { return nil }
                return Access(station: other.id, walkMinutes: Walking.minutes(forMetres: metres * Walking.detour))
            }
        }
        footpaths = paths
    }

    // MARK: Planning

    /// Journeys for a request, best first by the preference. Empty when nothing runs (screen 23).
    public func plan(_ request: PlanRequest) throws -> [Journey] {
        let day = ServiceDay(request.time, calendar: clock.calendar)
        let scan = try scan(for: day)
        let results = options(scan: scan, origins: access(near: request.from.coordinate),
                              destinations: access(near: request.to.coordinate),
                              time: minutes(of: request.time, on: day), arriveBy: request.arriveBy)
        var journeys = try results.compactMap { try journey(from: $0, day: day, request: request) }
        if let walk = walkOnly(request, quickestBus: journeys.map(\.minutes).min()) {
            journeys.append(walk)
        }
        return Self.ranked(journeys, by: request.preference, arriveBy: request.arriveBy)
    }

    /// Up to four bus options: one per set of trips, none beaten by another on both leave and arrival time.
    private func options(scan: ConnectionScan, origins: [Access], destinations: [Access],
                         time: Int, arriveBy: Bool) -> [RouteResult] {
        func route(_ at: Int) -> RouteResult? {
            scan.route(origins: origins, destinations: destinations, departAt: at)
        }
        // Earliest arrival alone may leave needlessly early: leave as late as possible for the same arrival.
        func latest(_ first: RouteResult) -> RouteResult {
            var result = first
            for _ in 0..<30 {
                guard let later = route(result.leaveAt + 1), later.arrival == result.arrival else { break }
                result = later
            }
            return result
        }

        // One option per set of trips (boarding the same buses at another stop is not a new option).
        var byTrips: [[Int]: RouteResult] = [:]
        var order: [[Int]] = []
        func keep(_ result: RouteResult, better: (RouteResult, RouteResult) -> Bool) {
            if let known = byTrips[result.trips] {
                if better(result, known) { byTrips[result.trips] = result }
            } else {
                byTrips[result.trips] = result
                order.append(result.trips)
            }
        }
        if !arriveBy {
            var at = time
            for _ in 0..<10 where byTrips.count < Self.maxOptions {
                guard let result = route(at).map(latest) else { break }
                keep(result) { $0.arrival - $0.leaveAt < $1.arrival - $1.leaveAt }
                at = result.leaveAt + 1
            }
        } else {
            // Scan departures from 3 h before and keep those arriving in time.
            var at = max(time - 180, 0)
            for _ in 0..<40 {
                guard let result = route(at), result.arrival <= time else { break }
                keep(result) { $0.leaveAt > $1.leaveAt }
                at = result.leaveAt + 1
            }
        }
        let all = order.compactMap { byTrips[$0] }
        // Drop options another one beats: leaving no earlier and arriving no later.
        let kept = all.filter { result in
            !all.contains { other in
                other != result && other.leaveAt >= result.leaveAt && other.arrival <= result.arrival
                    && (other.leaveAt > result.leaveAt || other.arrival < result.arrival)
            }
        }
        return arriveBy ? Array(kept.sorted { $0.leaveAt > $1.leaveAt }.prefix(Self.maxOptions)) : kept
    }

    // MARK: Building blocks

    /// Stations within a 15-minute walk (at least the nearest two, at most twelve).
    func access(near point: Coordinate) -> [Access] {
        let maxMetres = Double(Self.maxAccessMinutes) * Walking.metresPerMinute
        return store.stations
            .map { (station: $0, metres: Walking.estimatedMetres(from: point, to: $0.coordinate)) }
            .sorted { $0.metres < $1.metres }
            .enumerated()
            .filter { index, near in index < 2 || near.metres <= maxMetres }
            .prefix(12)
            .map { _, near in
                // Standing at the stop (under 40 m) counts as no walk.
                let minutes = near.metres < 40 ? 0 : Walking.minutes(forMetres: near.metres)
                return Access(station: near.station.id, walkMinutes: minutes)
            }
    }

    private func minutes(of date: Date, on day: ServiceDay) -> Int {
        clock.runningDays(at: date).first { $0.day == day }?.minutes ?? 0
    }

    func scan(for day: ServiceDay) throws -> ConnectionScan {
        if let cached = cache.withLock({ $0 }), cached.day == day { return cached.scan }
        var connections: [Connection] = []
        try queue.read { db in
            connections += try Self.connections(db, runningOn: day, yesterday: false)
            // Yesterday's trips still running after midnight: negative ids, times shifted by a day.
            connections += try Self.connections(db, runningOn: day.previous, yesterday: true)
        }
        let scan = ConnectionScan(connections: connections, footpaths: footpaths)
        cache.withLock { $0 = (day, scan) }
        return scan
    }

    /// Rides between consecutive stops of every trip running on `day`.
    private static func connections(_ db: Database, runningOn day: ServiceDay, yesterday: Bool) throws -> [Connection] {
        let sign = yesterday ? -1 : 1, shift = yesterday ? -ServiceClock.minutesPerDay : 0
        let rows = try Row.fetchCursor(db, sql: """
            SELECT st.trip_id, p.station_id, st.arrival, st.departure
            FROM stop_time st
            JOIN platform p ON p.id = st.platform_id
            JOIN trip t ON t.id = st.trip_id
            JOIN service_date sd ON sd.service_id = t.service_id AND sd.date = ?
            ORDER BY st.trip_id, st.seq
            """, arguments: [day.yyyymmdd])
        var result: [Connection] = []
        var previous: Connection?  // the last call read, as trip / station / departure
        while let row = try rows.next() {
            let trip: Int = row["trip_id"], station: Int = row["station_id"], arrival: Int = row["arrival"]
            if let last = previous, last.trip == trip, last.departure + shift >= 0 {
                result.append(Connection(trip: sign * trip, from: last.from, to: station,
                                         departure: last.departure + shift, arrival: arrival + shift))
            }
            previous = Connection(trip: trip, from: station, to: station, departure: row["departure"], arrival: arrival)
        }
        return result
    }

    /// The journey for a scan result, with real dates, stops and paths. nil if any ride cannot be matched
    /// to the timetable (should not happen: both come from the same data), so no option has a gap.
    private func journey(from result: RouteResult, day: ServiceDay, request: PlanRequest) throws -> Journey? {
        guard case let .ride(_, firstFrom, _, firstDeparture, _) = result.parts[0],
              let firstStation = store.station(id: firstFrom) else { return nil }
        var legs: [Leg] = []
        if result.access.walkMinutes > 0 {
            legs.append(.walk(walkLeg(from: request.from.coordinate, to: firstStation.coordinate,
                                      name: firstStation.shortName, end: clock.date(day, minutes: firstDeparture),
                                      minutes: result.access.walkMinutes)))
        }
        for part in result.parts {
            switch part {
            case let .ride(trip, from, to, departure, arrival):
                guard let ride = try rideLeg(trip: trip, from: from, to: to, minutes: departure...arrival, day: day)
                else { return nil }
                legs.append(.ride(ride))
            case let .transfer(from, to, minutes):
                guard let transfer = transferLeg(from: from, to: to, minutes: minutes, after: legs.last) else {
                    return nil
                }
                legs.append(.walk(transfer))
            }
        }
        if result.egress.walkMinutes > 0, let last = store.station(id: result.egress.station),
           let arrival = legs.last?.end {
            legs.append(.walk(walkLeg(from: last.coordinate, to: request.to.coordinate, name: request.to.name,
                                      end: arrival.addingTimeInterval(TimeInterval(result.egress.walkMinutes * 60)),
                                      minutes: result.egress.walkMinutes)))
        }
        return Journey(legs: legs)
    }

    /// The stops ridden on one trip, from boarding to alighting, with the matching piece of its shape.
    private func rideLeg(trip: Int, from: Int, to: Int, minutes: ClosedRange<Int>, day: ServiceDay) throws -> RideLeg? {
        // Negative ids are the previous service day's trips (see `connections`).
        guard let full = try store.trip(id: abs(trip), on: trip < 0 ? day.previous : day) else { return nil }
        let start = clock.date(day, minutes: minutes.lowerBound), end = clock.date(day, minutes: minutes.upperBound)
        guard let first = full.stops.firstIndex(where: { $0.station.id == from && $0.departure == start }),
              let last = full.stops[first...].firstIndex(where: { $0.station.id == to && $0.arrival == end })
        else { return nil }
        let stops = Array(full.stops[first...last])
        let path = Self.slice(full.shape, along: stops.map(\.platform.coordinate))
        return RideLeg(tripID: abs(trip), line: full.line, headsign: full.headsign, stops: stops, path: path)
    }

    /// Walking from one station to another to change buses, starting when the previous ride ends.
    private func transferLeg(from: Int, to: Int, minutes: Int, after previous: Leg?) -> WalkLeg? {
        guard let origin = store.station(id: from), let target = store.station(id: to), let start = previous?.end
        else { return nil }
        return onStreets(WalkLeg(start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                                 metres: Int(Walking.estimatedMetres(from: origin.coordinate, to: target.coordinate)),
                                 destinationName: target.shortName, path: [origin.coordinate, target.coordinate]))
    }

    private func walkLeg(from: Coordinate, to: Coordinate, name: String, end: Date, minutes: Int) -> WalkLeg {
        onStreets(WalkLeg(start: end.addingTimeInterval(TimeInterval(-minutes * 60)), end: end,
                          metres: Int(Walking.estimatedMetres(from: from, to: to)), destinationName: name,
                          path: [from, to]))
    }

    /// The leg with its real street path, steps and length when the walking router knows a way.
    /// Its times stay as planned, so the journey still fits the timetable.
    private func onStreets(_ leg: WalkLeg) -> WalkLeg {
        guard let from = leg.path.first, let to = leg.path.last, let route = walker?.route(from: from, to: to)
        else { return leg }
        var result = leg
        result.path = route.path
        result.steps = route.steps
        result.metres = Int(route.metres.rounded())
        return result
    }

    /// Walking the whole way: always for short trips (≤ 20 min), otherwise when about as quick as the bus.
    private func walkOnly(_ request: PlanRequest, quickestBus: Int?) -> Journey? {
        // The real street route when known (no timetable to fit, so its own time counts), else an estimate.
        let route = walker?.route(from: request.from.coordinate, to: request.to.coordinate)
        let metres = route?.metres ?? Walking.estimatedMetres(from: request.from.coordinate, to: request.to.coordinate)
        let minutes = Walking.minutes(forMetres: metres)
        guard minutes <= 20 || (minutes <= 45 && (quickestBus.map { minutes <= $0 + 5 } ?? true)) else { return nil }
        let duration = TimeInterval(minutes * 60)
        let start = request.arriveBy ? request.time.addingTimeInterval(-duration) : request.time
        return Journey(legs: [.walk(WalkLeg(start: start, end: start.addingTimeInterval(duration),
                                            metres: Int(metres.rounded()), destinationName: request.to.name,
                                            steps: route?.steps ?? [],
                                            path: route?.path ?? [request.from.coordinate, request.to.coordinate]))])
    }
}
