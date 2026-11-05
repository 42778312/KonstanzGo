import Foundation
import GRDB
import Synchronization

/// The buses running now, placed by the timetable (no live positions: the app works offline).
/// Each day's trips are read once; a trip's trajectory is built the first time it is needed.
public final class VehicleTracker: Sendable {
    struct Call {
        var coordinate: Coordinate
        var arrival: Int
        var departure: Int
    }

    struct TripCalls {
        var trip: Int
        var route: Int
        var headsign: String
        var shape: Int?
        var calls: [Call]
        /// First and last timetable minute, for a quick "is it running" check.
        var first: Int { calls[0].arrival }
        var last: Int { calls[calls.count - 1].arrival }
    }

    private struct Cache {
        var days: [ServiceDay: [TripCalls]] = [:]
        var trajectories: [String: Trajectory] = [:]
        var shapes: [Int: [Coordinate]] = [:]
    }

    private let store: TimetableStore
    private let queue: DatabaseQueue
    private let clock: ServiceClock
    /// The street network, for buses between stops their route shape doesn't connect.
    private let streets: WalkRouter?
    private let cache = Mutex(Cache())

    public init(store: TimetableStore, url: URL, clock: ServiceClock = ServiceClock(),
                streets: WalkRouter? = nil) throws {
        self.store = store
        self.clock = clock
        self.streets = streets
        var config = Configuration()
        config.readonly = true
        queue = try DatabaseQueue(path: url.path, configuration: config)
    }

    /// Every trip on the road at `date`, today's and yesterday's night trips. `cityOnly` keeps Konstanz lines.
    /// `delays` (seconds per trip, from live reports) put late buses where they really are; `cancelled` trips
    /// aren't on the road at all.
    public func positions(at date: Date, cityOnly: Bool = false, delays: [Int: Double] = [:],
                          cancelled: Set<Int> = []) throws -> [VehiclePosition] {
        var result: [VehiclePosition] = []
        // Trajectories run in wall-clock seconds of their own service day, like the timetable
        // (yesterday's night trips past 24:00), so each day is asked in its own seconds.
        for (day, minutes) in clock.runningDays(at: date) {
            let seconds = Double(minutes) * 60 + Self.secondsIntoMinute(date)
            for trip in try trips(on: day) where !cancelled.contains(trip.trip) {
                let delay = delays[trip.trip] ?? 0
                let late = Int((delay / 60).rounded(.up))
                guard trip.first + late <= minutes + 1, trip.last + late >= minutes - 1,
                      let line = store.line(id: trip.route), !cityOnly || line.isCity else { continue }
                if var position = try trajectory(trip, line: line, day: day)?.position(at: seconds - delay) {
                    if delays[trip.trip] != nil { position.isEstimated = false }
                    result.append(position)
                }
            }
        }
        return result
    }

    /// Where one trip's bus is (screens 11, 17, 21), or nil when it is not running then.
    public func position(ofTrip tripID: Int, on day: ServiceDay, at date: Date) throws -> VehiclePosition? {
        guard let minutes = clock.runningDays(at: date).first(where: { $0.day == day })?.minutes,
              let trip = try trips(on: day).first(where: { $0.trip == tripID }), let line = store.line(id: trip.route)
        else { return nil }
        let seconds = Double(minutes) * 60 + Self.secondsIntoMinute(date)
        return try trajectory(trip, line: line, day: day)?.position(at: seconds)
    }

    private static func secondsIntoMinute(_ date: Date) -> Double {
        let seconds = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        return seconds < 0 ? seconds + 60 : seconds
    }

    // MARK: Loading

    func trips(on day: ServiceDay) throws -> [TripCalls] {
        if let cached = cache.withLock({ $0.days[day] }) { return cached }
        let trips = try queue.read { db -> [TripCalls] in
            var trips: [TripCalls] = []
            let rows = try Row.fetchCursor(db, sql: """
                SELECT st.trip_id, st.arrival, st.departure, p.lat, p.lon, t.route_id, t.headsign, t.shape_id
                FROM stop_time st
                JOIN platform p ON p.id = st.platform_id
                JOIN trip t ON t.id = st.trip_id
                JOIN service_date sd ON sd.service_id = t.service_id AND sd.date = ?
                ORDER BY st.trip_id, st.seq
                """, arguments: [day.yyyymmdd])
            while let row = try rows.next() {
                let call = Call(coordinate: Coordinate(latitude: row["lat"], longitude: row["lon"]),
                                arrival: row["arrival"], departure: row["departure"])
                let trip: Int = row["trip_id"]
                if trips.last?.trip == trip {
                    trips[trips.count - 1].calls.append(call)
                } else {
                    trips.append(TripCalls(trip: trip, route: row["route_id"],
                                           headsign: store.displayName(headsign: row["headsign"]),
                                           shape: row["shape_id"], calls: [call]))
                }
            }
            return trips
        }
        cache.withLock { cache in
            // Keep the last few days only (today, yesterday, and the one being looked at).
            if cache.days.count > 3 { cache.days.removeAll(); cache.trajectories.removeAll() }
            cache.days[day] = trips
        }
        return trips
    }

    func trajectory(_ trip: TripCalls, line: Line, day: ServiceDay) throws -> Trajectory? {
        let key = "\(day.yyyymmdd)/\(trip.trip)"
        if let cached = cache.withLock({ $0.trajectories[key] }) { return cached }
        let shape = try trip.shape.map(shape(id:)) ?? []
        let trajectory = Trajectory(tripID: trip.trip, line: line, headsign: trip.headsign,
                                    calls: trip.calls.map { TimedStop(coordinate: $0.coordinate, arrival: $0.arrival,
                                                                      departure: $0.departure) },
                                    shape: shape,
                                    streets: line.mode == .bus ? streets.map { router in
                                        { router.route(from: $0, to: $1)?.path }
                                    } : nil)
        if let trajectory { cache.withLock { $0.trajectories[key] = trajectory } }
        return trajectory
    }

    private func shape(id: Int) throws -> [Coordinate] {
        if let cached = cache.withLock({ $0.shapes[id] }) { return cached }
        let points = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT points FROM shape WHERE id = ?", arguments: [id])
        }
        let shape = points.map(Polyline.decode) ?? []
        cache.withLock { $0.shapes[id] = shape }
        return shape
    }
}
