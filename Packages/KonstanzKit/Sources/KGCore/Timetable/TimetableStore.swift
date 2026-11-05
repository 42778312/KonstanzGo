import Foundation
import GRDB

/// Read-only access to the bundled timetable (`timetable.db`).
///
/// Stations, platforms and lines are small (a few hundred rows) and loaded once when the store opens;
/// departures and trips are queried on demand. Safe to use from any thread.
public final class TimetableStore: Sendable {
    public let stations: [Station]
    public let lines: [Line]
    private let stationsByID: [Int: Station]
    private let platformsByID: [Int: Platform]
    private let platformsByStation: [Int: [Platform]]
    private let linesByID: [Int: Line]
    private let queue: DatabaseQueue
    private let clock: ServiceClock

    public init(url: URL, clock: ServiceClock = ServiceClock()) throws {
        var config = Configuration()
        config.readonly = true
        queue = try DatabaseQueue(path: url.path, configuration: config)
        self.clock = clock

        let (stations, platforms, lines) = try queue.read { db in
            let stations = try Row.fetchAll(db, sql: "SELECT id, name, short_name, lat, lon FROM station").map {
                Station(id: $0["id"], name: $0["name"], shortName: $0["short_name"],
                        coordinate: Coordinate(latitude: $0["lat"], longitude: $0["lon"]))
            }
            let platforms = try Row.fetchAll(
                db, sql: "SELECT id, station_id, code, lat, lon, direction FROM platform"
            ).map { row in
                Platform(id: row["id"], stationID: row["station_id"], code: Self.nonEmpty(row["code"]),
                         coordinate: Coordinate(latitude: row["lat"], longitude: row["lon"]),
                         direction: Self.nonEmpty(row["direction"]))
            }
            let lines = try Row.fetchAll(db, sql: "SELECT id, short_name, long_name, is_city, type, agency FROM route").map {
                Line(id: $0["id"], name: $0["short_name"], longName: $0["long_name"], isCity: $0["is_city"],
                     mode: VehicleMode(routeType: $0["type"]), agency: $0["agency"])
            }
            return (stations, platforms, lines)
        }
        self.stations = stations.sorted { $0.name < $1.name }
        self.lines = lines.sorted { LineOrder.precedes($0.name, $1.name) }
        stationsByID = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        platformsByID = Dictionary(uniqueKeysWithValues: platforms.map { ($0.id, $0) })
        platformsByStation = Dictionary(grouping: platforms, by: \.stationID)
        linesByID = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })
    }

    // MARK: Lookups

    public func station(id: Int) -> Station? { stationsByID[id] }
    public func platform(id: Int) -> Platform? { platformsByID[id] }
    public func platforms(of stationID: Int) -> [Platform] { platformsByStation[stationID] ?? [] }
    public func line(id: Int) -> Line? { linesByID[id] }

    /// Stations within `metres` of a point, nearest first.
    public func stations(near point: Coordinate, within metres: Double, limit: Int = 10) -> [(Station, Double)] {
        stations.map { ($0, $0.coordinate.distance(to: point)) }
            .filter { $0.1 <= metres }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Departures

    /// Departures from any platform of a station, from `date` on, in time order.
    /// Arrivals at a trip's last stop are left out: nobody can get on there.
    public func departures(at stationID: Int, from date: Date, limit: Int = 20,
                           within hours: Int = 6) throws -> [Departure] {
        let platformIDs = platforms(of: stationID).map(\.id)
        guard !platformIDs.isEmpty else { return [] }
        let placeholders = platformIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT st.trip_id, st.departure, st.platform_id, t.headsign, t.route_id
            FROM stop_time st
            JOIN trip t ON t.id = st.trip_id
            JOIN service_date sd ON sd.service_id = t.service_id AND sd.date = ?
            WHERE st.platform_id IN (\(placeholders)) AND st.departure >= ? AND st.departure < ?
              AND EXISTS (SELECT 1 FROM stop_time later WHERE later.trip_id = st.trip_id AND later.seq > st.seq)
            ORDER BY st.departure
            LIMIT ?
            """
        var result: [Departure] = []
        try queue.read { db in
            for (day, minutes) in clock.upcomingDays(at: date) where minutes + hours * 60 > 0 {
                var arguments: [any DatabaseValueConvertible] = [day.yyyymmdd]
                arguments += platformIDs
                arguments += [minutes, minutes + hours * 60, limit]
                for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)) {
                    guard let line = linesByID[row["route_id"]], let platform = platformsByID[row["platform_id"]] else {
                        continue
                    }
                    result.append(Departure(
                        tripID: row["trip_id"], line: line, headsign: displayName(headsign: row["headsign"]),
                        platform: platform, scheduled: clock.date(day, minutes: row["departure"])
                    ))
                }
            }
        }
        return Array(result.sorted { ($0.scheduled, $0.line.name) < ($1.scheduled, $1.line.name) }.prefix(limit))
    }

    /// The next times per line and direction (screen 09 "Linien": "Richtung Universität · 14:21 · 14:36 · 14:51").
    public func departuresByLine(at stationID: Int, from date: Date, perDirection: Int = 3) throws -> [LineDirection] {
        let all = try departures(at: stationID, from: date, limit: 400, within: 4)
        var groups: [String: LineDirection] = [:]
        var order: [String] = []
        for departure in all {
            let key = "\(departure.line.id)|\(departure.headsign)"
            if groups[key] == nil {
                groups[key] = LineDirection(line: departure.line, headsign: departure.headsign, departures: [])
                order.append(key)
            }
            if groups[key]?.departures.count ?? 0 < perDirection {
                groups[key]?.departures.append(departure)
            }
        }
        return order.compactMap { groups[$0] }.sorted {
            LineOrder.precedes($0.line.name, $1.line.name)
                || ($0.line.name == $1.line.name && $0.headsign < $1.headsign)
        }
    }

    /// Lines that stop at a station, in badge order ("1", "5", "9", "12").
    public func lines(at stationID: Int) throws -> [Line] {
        let platformIDs = platforms(of: stationID).map(\.id)
        guard !platformIDs.isEmpty else { return [] }
        let placeholders = platformIDs.map { _ in "?" }.joined(separator: ",")
        let ids = try queue.read { db in
            try Int.fetchAll(db, sql: """
                SELECT DISTINCT t.route_id FROM stop_time st JOIN trip t ON t.id = st.trip_id
                WHERE st.platform_id IN (\(placeholders))
                """, arguments: StatementArguments(platformIDs))
        }
        return ids.compactMap { linesByID[$0] }.sorted { LineOrder.precedes($0.name, $1.name) }
    }

    // MARK: Trips

    /// A trip on one service day with every stop and its shape (screen 17).
    public func trip(id: Int, on day: ServiceDay) throws -> Trip? {
        try queue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT t.route_id, t.headsign, s.points FROM trip t LEFT JOIN shape s ON s.id = t.shape_id
                WHERE t.id = ?
                """, arguments: [id]),
                let line = linesByID[row["route_id"]] else { return nil }
            let stops = try Row.fetchAll(db, sql: """
                SELECT platform_id, arrival, departure FROM stop_time WHERE trip_id = ? ORDER BY seq
                """, arguments: [id]).compactMap { stop -> TripStop? in
                guard let platform = platformsByID[stop["platform_id"]],
                      let station = stationsByID[platform.stationID] else { return nil }
                return TripStop(station: station, platform: platform,
                                arrival: clock.date(day, minutes: stop["arrival"]),
                                departure: clock.date(day, minutes: stop["departure"]))
            }
            let points: String? = row["points"]
            return Trip(id: id, line: line, headsign: displayName(headsign: row["headsign"]), stops: stops,
                        shape: points.map(Polyline.decode) ?? [])
        }
    }

    /// The next bus from `date` on that goes directly from one station to another, with its arrival
    /// ("Nach Hause" widget). Looks at today's and yesterday's service, and tomorrow's night buses.
    public func nextDirectDeparture(from fromStation: Int, to toStation: Int,
                                    after date: Date) throws -> (departure: Departure, arrival: Date)? {
        let from = platforms(of: fromStation).map(\.id), to = platforms(of: toStation).map(\.id)
        guard !from.isEmpty, !to.isEmpty else { return nil }
        let fromList = from.map { _ in "?" }.joined(separator: ","), toList = to.map { _ in "?" }.joined(separator: ",")
        var best: (departure: Departure, arrival: Date)?
        try queue.read { db in
            for (day, minutes) in clock.upcomingDays(at: date) {
                let before = minutes < 0 ? ServiceClock.nightMinutes : Int.max
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT a.trip_id, a.departure, a.platform_id, b.arrival, t.headsign, t.route_id
                    FROM stop_time a
                    JOIN stop_time b ON b.trip_id = a.trip_id AND b.seq > a.seq AND b.platform_id IN (\(toList))
                    JOIN trip t ON t.id = a.trip_id
                    JOIN service_date sd ON sd.service_id = t.service_id AND sd.date = ?
                    WHERE a.platform_id IN (\(fromList)) AND a.departure >= ? AND a.departure < ?
                    ORDER BY b.arrival LIMIT 1
                    """, arguments: StatementArguments(to + [day.yyyymmdd] + from + [minutes, before])),
                    let line = linesByID[row["route_id"]], let platform = platformsByID[row["platform_id"]]
                else { continue }
                let departure = Departure(tripID: row["trip_id"], line: line,
                                          headsign: displayName(headsign: row["headsign"]), platform: platform,
                                          scheduled: clock.date(day, minutes: row["departure"]))
                let arrival = clock.date(day, minutes: row["arrival"])
                if let current = best, current.arrival <= arrival { continue }
                best = (departure, arrival)
            }
        }
        return best
    }

    /// The first bus on `day` that goes directly from a station to another (screen 23:
    /// "Erster Bus morgen um 05:42"). nil when none runs that day.
    public func firstDirectDeparture(from fromStation: Int, to toStation: Int,
                                     on day: ServiceDay) throws -> Departure? {
        let from = platforms(of: fromStation).map(\.id), to = platforms(of: toStation).map(\.id)
        guard !from.isEmpty, !to.isEmpty else { return nil }
        let fromList = from.map { _ in "?" }.joined(separator: ","), toList = to.map { _ in "?" }.joined(separator: ",")
        return try queue.read { db -> Departure? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT a.trip_id, a.departure, a.platform_id, t.headsign, t.route_id
                FROM stop_time a
                JOIN stop_time b ON b.trip_id = a.trip_id AND b.seq > a.seq AND b.platform_id IN (\(toList))
                JOIN trip t ON t.id = a.trip_id
                JOIN service_date sd ON sd.service_id = t.service_id AND sd.date = ?
                WHERE a.platform_id IN (\(fromList))
                ORDER BY a.departure LIMIT 1
                """, arguments: StatementArguments(to + [day.yyyymmdd] + from)),
                let line = linesByID[row["route_id"]], let platform = platformsByID[row["platform_id"]]
            else { return nil }
            return Departure(tripID: row["trip_id"], line: line, headsign: displayName(headsign: row["headsign"]),
                             platform: platform, scheduled: clock.date(day, minutes: row["departure"]))
        }
    }

    // MARK: Names

    /// The destination as people say it: a station's short name ("Konstanz Universität" → "Universität"),
    /// otherwise without the leading "Konstanz ".
    public func displayName(headsign: String) -> String {
        if let station = stations.first(where: { $0.name == headsign }) { return station.shortName }
        for prefix in ["Konstanz, ", "Konstanz "] where headsign.hasPrefix(prefix) {
            return String(headsign.dropFirst(prefix.count))
        }
        return headsign
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

/// One line in one direction at a station, with its next departures.
public struct LineDirection: Sendable, Hashable, Identifiable {
    public var line: Line
    public var headsign: String
    public var departures: [Departure]
    public var id: String { "\(line.id)|\(headsign)" }
}

/// Badge order for line names: by number, then by the rest ("1" < "5" < "9" < "9A" < "12" < "N").
public enum LineOrder {
    public static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let left = split(lhs), right = split(rhs)
        switch (left.number, right.number) {
        case let (leftNumber?, rightNumber?):
            return leftNumber != rightNumber ? leftNumber < rightNumber : left.rest < right.rest
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return lhs < rhs
        }
    }

    private static func split(_ name: String) -> (number: Int?, rest: String) {
        let digits = name.prefix { $0.isNumber }
        return (Int(digits), String(name.dropFirst(digits.count)))
    }
}
