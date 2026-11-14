import Foundation
import KGLiveAPI

/// `timetable.db`, loaded into memory once at boot. Immutable afterwards, so every actor can read it freely.
public final class Timetable: Sendable {
    public struct Station: Sendable {
        public let id: Int
        public let name: String
        /// The stop area most of its platforms belong to ("de:08335:11918"); the one to ask the source for.
        public let gid: String
        /// Every stop area its platforms belong to (Konstanz Bahnhof has a bus and a train area).
        public let gids: Set<String>
    }

    public struct Trip: Sendable {
        public let id: Int
        public let line: String
        public let headsign: String
        public let serviceID: Int
        public let isCity: Bool
        public let firstPlatform: String
        public let firstDeparture: Int
        public let lastArrival: Int
        /// Platform id and departure minute of each stop, in order.
        public let stops: [(platform: Int, departure: Int)]

        public func key(on serviceDay: Int) -> String {
            TripKey.make(serviceDate: serviceDay, line: line, firstPlatform: firstPlatform, firstDeparture: firstDeparture)
        }
    }

    struct Platform: Sendable {
        let station: Int
        let gid: String
    }

    struct StopKey: Hashable {
        let station: Int
        let line: String
        let minute: Int
    }

    public let feedVersion: String
    public let feedStart: Int
    public let feedEnd: Int
    public let stations: [Int: Station]
    public let trips: [Int: Trip]
    let platforms: [Int: Platform]
    let platformByGID: [String: Int]
    let stationsByGID: [String: [Int]]
    let serviceDays: [Int: Set<Int>]
    /// City trips by where and when they leave a station.
    let index: [StopKey: [Int]]
    let cityTrips: [Trip]
    let cityLines: Set<String>
    /// "9" → ["9A", "9B"]: EFA-BW names both variants by the base number.
    let lineVariants: [String: [String]]

    public var stopTimeCount: Int { trips.values.reduce(0) { $0 + $1.stops.count } }

    public convenience init(path: String) throws {
        let reader = try SQLiteReader(path: path)
        var meta: [String: String] = [:]
        try reader.each("SELECT key, value FROM meta") { meta[$0.string(0) ?? ""] = $0.string(1) }
        var platforms: [Int: Platform] = [:]
        try reader.each("SELECT id, station_id, gtfs_id FROM platform") {
            platforms[$0.int(0)] = Platform(station: $0.int(1), gid: $0.string(2) ?? "")
        }
        var names: [Int: String] = [:]
        try reader.each("SELECT id, name FROM station") { names[$0.int(0)] = $0.string(1) ?? "" }
        var routes: [Int: (line: String, isCity: Bool)] = [:]
        try reader.each("SELECT id, short_name, is_city FROM route") { routes[$0.int(0)] = ($0.string(1) ?? "", $0.int(2) == 1) }
        var serviceDays: [Int: Set<Int>] = [:]
        try reader.each("SELECT service_id, date FROM service_date") { serviceDays[$0.int(0), default: []].insert($0.int(1)) }
        var stopsByTrip: [Int: [(platform: Int, arrival: Int, departure: Int)]] = [:]
        try reader.each("SELECT trip_id, platform_id, arrival, departure FROM stop_time ORDER BY trip_id, seq") {
            stopsByTrip[$0.int(0), default: []].append(($0.int(1), $0.int(2), $0.int(3)))
        }
        var trips: [Int: Trip] = [:]
        try reader.each("SELECT id, route_id, service_id, headsign FROM trip") { row in
            let id = row.int(0)
            guard let route = routes[row.int(1)], let stops = stopsByTrip[id], let first = stops.first,
                  let last = stops.last else { return }
            trips[id] = Trip(id: id, line: route.line, headsign: row.string(3) ?? "", serviceID: row.int(2),
                             isCity: route.isCity, firstPlatform: platforms[first.platform]?.gid ?? "",
                             firstDeparture: first.departure, lastArrival: last.arrival,
                             stops: stops.map { ($0.platform, $0.departure) })
        }
        self.init(meta: meta, names: names, platforms: platforms, trips: trips, serviceDays: serviceDays)
    }

    init(meta: [String: String], names: [Int: String], platforms: [Int: Platform], trips: [Int: Trip],
         serviceDays: [Int: Set<Int>]) {
        feedVersion = meta["feed_version"] ?? "unknown"
        feedStart = Int(meta["feed_start"] ?? "") ?? 0
        feedEnd = Int(meta["feed_end"] ?? "") ?? 0
        self.platforms = platforms
        self.trips = trips
        self.serviceDays = serviceDays
        var platformByGID: [String: Int] = [:]
        var areas: [Int: [String]] = [:]
        for (id, platform) in platforms {
            platformByGID[platform.gid] = id
            areas[platform.station, default: []].append(TripKey.stopGID(of: platform.gid))
        }
        self.platformByGID = platformByGID
        var stations: [Int: Station] = [:]
        var stationsByGID: [String: [Int]] = [:]
        for (id, name) in names {
            let list = areas[id] ?? []
            let counts = Dictionary(grouping: list, by: { $0 }).mapValues(\.count)
            let main = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? ""
            stations[id] = Station(id: id, name: name, gid: main, gids: Set(list))
            for gid in Set(list) { stationsByGID[gid, default: []].append(id) }
        }
        self.stations = stations
        self.stationsByGID = stationsByGID
        var index: [StopKey: [Int]] = [:]
        for trip in trips.values where trip.isCity {
            for stop in trip.stops {
                guard let station = platforms[stop.platform]?.station else { continue }
                index[StopKey(station: station, line: trip.line, minute: stop.departure), default: []].append(trip.id)
            }
        }
        self.index = index
        cityTrips = trips.values.filter(\.isCity).sorted { $0.id < $1.id }
        cityLines = Set(cityTrips.map(\.line))
        var variants: [String: [String]] = [:]
        for line in cityLines {
            let base = String(line.prefix { $0.isNumber })
            if !base.isEmpty, base != line, line.dropFirst(base.count).allSatisfy(\.isLetter) {
                variants[base, default: []].append(line)
            }
        }
        lineVariants = variants.mapValues { $0.sorted() }
    }

    // MARK: Lookups

    /// The station of a platform or stop area id from the source. Tries the exact platform, then shorter ids.
    public func station(forPlatform gid: String) -> Int? {
        if let platform = platformByGID[gid] { return platforms[platform]?.station }
        var parts = gid.split(separator: ":", omittingEmptySubsequences: false)
        while parts.count > 3 {
            parts.removeLast()
            if let platform = platformByGID[parts.joined(separator: ":")] { return platforms[platform]?.station }
        }
        return stationsByGID[TripKey.stopGID(of: gid)]?.first
    }

    /// The stations that belong to a stop gid ("de:08335:11918").
    public func stations(forGID gid: String) -> [Int] { stationsByGID[gid] ?? [] }

    public func runs(_ trip: Trip, on day: Int) -> Bool { serviceDays[trip.serviceID]?.contains(day) == true }

    /// City trips of `line` that leave `station` at `planned`, with the service day they run on. When the line
    /// itself has none, its lettered variants ("9" → "9A", "9B") at the same stop and minute.
    func candidates(station: Int, line: String, planned: Date) -> [(trip: Trip, day: Int)] {
        let exact = candidates(station: station, lines: [line], planned: planned)
        guard exact.isEmpty, let variants = lineVariants[line] else { return exact }
        return candidates(station: station, lines: variants, planned: planned)
    }

    private func candidates(station: Int, lines: [String], planned: Date) -> [(trip: Trip, day: Int)] {
        BerlinTime.serviceTimes(of: planned).flatMap { time in
            lines.flatMap { line in
                (index[StopKey(station: station, line: line, minute: time.minute)] ?? []).compactMap { id in
                    trips[id].flatMap { runs($0, on: time.day) ? ($0, time.day) : nil }
                }
            }
        }
    }

    /// Whether `line` is a city line of this timetable.
    public func isCityLine(_ line: String) -> Bool { cityLines.contains(line) || lineVariants[line] != nil }

    /// City trips running at `date` or starting within `ahead` minutes, with their service day.
    public func runningCityTrips(at date: Date, ahead: Int = 0) -> [(trip: Trip, day: Int)] {
        BerlinTime.serviceTimes(of: date).flatMap { time in
            cityTrips.compactMap { trip in
                trip.firstDeparture <= time.minute + ahead && trip.lastArrival >= time.minute && runs(trip, on: time.day)
                    ? (trip, time.day) : nil
            }
        }
    }

    /// The moment a trip ends on a service day.
    public func end(of trip: Trip, on day: Int) -> Date { BerlinTime.date(serviceDay: day, minute: trip.lastArrival) }

    /// Planned departures from the stations of a stop gid, from `date` on, soonest first.
    public func scheduledDepartures(gid: String, from date: Date, limit: Int) -> [(trip: Trip, day: Int, platform: String, at: Date)] {
        let wanted = Set(stations(forGID: gid))
        guard !wanted.isEmpty else { return [] }
        var found: [(trip: Trip, day: Int, platform: String, at: Date)] = []
        for time in BerlinTime.serviceTimes(of: date) {
            for trip in trips.values where runs(trip, on: time.day) {
                for stop in trip.stops.dropLast() where stop.departure >= time.minute && stop.departure < time.minute + 180 {
                    guard let platform = platforms[stop.platform], wanted.contains(platform.station) else { continue }
                    found.append((trip, time.day, platform.gid, BerlinTime.date(serviceDay: time.day, minute: stop.departure)))
                }
            }
        }
        return Array(found.sorted { ($0.at, $0.trip.line) < ($1.at, $1.trip.line) }.prefix(limit))
    }

    // MARK: Hubs

    public struct Hubs: Sendable {
        public let stations: [Station]
        /// Share of all 15-minute stretches of city trips that pass at least one hub.
        public let coverage: Double
    }

    /// The stops to poll. One answer from a stop shows the buses due there in the next minutes, so a trip is only
    /// seen near the hubs it passes. Greedy set cover over every 15-minute stretch of every city trip: take the stop
    /// that sees the most stretches not yet seen, until `target` of them are covered, at least `minimum` and at most
    /// `maximum` stops.
    public func hubs(target: Double = 0.9, minimum: Int = 12, maximum: Int = 15) -> Hubs {
        struct Stretch: Hashable {
            let trip: Int
            let part: Int
        }
        var seen: [Int: Set<Stretch>] = [:]
        var all = Set<Stretch>()
        for trip in cityTrips {
            for stop in trip.stops {
                let stretch = Stretch(trip: trip.id, part: (stop.departure - trip.firstDeparture) / 15)
                all.insert(stretch)
                guard let station = platforms[stop.platform]?.station,
                      TripKey.isStopGID(stations[station]?.gid ?? "") else { continue }
                seen[station, default: []].insert(stretch)
            }
        }
        var covered = Set<Stretch>()
        var chosen: [Station] = []
        while chosen.count < maximum, chosen.count < minimum || Double(covered.count) < target * Double(all.count) {
            let best = seen.max { lhs, rhs in
                (lhs.value.subtracting(covered).count, rhs.key) < (rhs.value.subtracting(covered).count, lhs.key)
            }
            guard let best, !best.value.subtracting(covered).isEmpty, let station = stations[best.key] else { break }
            chosen.append(station)
            covered.formUnion(best.value)
            seen[best.key] = nil
        }
        return Hubs(stations: chosen, coverage: all.isEmpty ? 0 : Double(covered.count) / Double(all.count))
    }
}
