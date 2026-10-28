import Foundation

/// A ride between two consecutive stops of a trip. Times are timetable minutes of the planning day
/// (negative for the previous day's trips running past midnight).
public struct Connection: Sendable, Hashable {
    /// Trip id; negated for trips of the previous service day, so both runs stay apart.
    public var trip: Int
    public var from: Int
    public var to: Int
    public var departure: Int
    public var arrival: Int

    public init(trip: Int, from: Int, to: Int, departure: Int, arrival: Int) {
        self.trip = trip
        self.from = from
        self.to = to
        self.departure = departure
        self.arrival = arrival
    }
}

/// A station reachable on foot: start or end of a journey, or a transfer.
public struct Access: Sendable, Hashable {
    public var station: Int
    public var walkMinutes: Int

    public init(station: Int, walkMinutes: Int) {
        self.station = station
        self.walkMinutes = walkMinutes
    }
}

public enum RoutePart: Sendable, Hashable {
    case ride(trip: Int, from: Int, to: Int, departure: Int, arrival: Int)
    case transfer(from: Int, to: Int, minutes: Int)
}

/// Walk to `access`, take `parts` (always starting with a ride), walk from `egress`; arrive at `arrival`.
public struct RouteResult: Sendable, Hashable {
    public var access: Access
    public var parts: [RoutePart]
    public var egress: Access
    /// At the target, in timetable minutes.
    public var arrival: Int

    /// Trips ridden, in order. Two results with the same trips are the same option.
    public var trips: [Int] {
        parts.compactMap { if case let .ride(trip, _, _, _, _) = $0 { trip } else { nil } }
    }

    /// When to leave the start point.
    public var leaveAt: Int {
        guard case let .ride(_, _, _, departure, _) = parts[0] else { return arrival }
        return departure - access.walkMinutes
    }
}

/// Earliest-arrival routing with the Connection Scan Algorithm (Dibbelt et al.): one pass over the
/// day's connections sorted by departure. A few milliseconds per query for a city.
/// Same algorithm and rules as the Android app's `ConnectionScanRouter`.
public struct ConnectionScan: Sendable {
    /// Sorted by departure, then arrival.
    let connections: [Connection]
    /// Per station, the stations a short walk away.
    let footpaths: [Int: [Access]]
    /// Minutes needed to change buses at the same station.
    let minChange: Int

    public init(connections: [Connection], footpaths: [Int: [Access]], minChange: Int = 1) {
        self.connections = connections.sorted { ($0.departure, $0.arrival) < ($1.departure, $1.arrival) }
        self.footpaths = footpaths
        self.minChange = minChange
    }

    private enum Reached {
        case start(Access)
        case byRide(enter: Int, exit: Int)
        case byWalk(from: Int, minutes: Int)
    }

    // One pass of the published algorithm, kept in one piece so it can be checked against the paper.
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// The best route leaving at `departAt` or later, or nil when no destination can be reached by bus.
    public func route(origins: [Access], destinations: [Access], departAt: Int) -> RouteResult? {
        var earliest: [Int: Int] = [:]
        var reached: [Int: Reached] = [:]
        var arrivedByRide: Set<Int> = []
        var tripEntered: [Int: Int] = [:]
        let egress = Dictionary(destinations.map { ($0.station, $0.walkMinutes) }, uniquingKeysWith: min)
        var best = Int.max
        var bestStation: Int?

        func offer(_ station: Int) {
            guard let walk = egress[station], let at = earliest[station] else { return }
            if at + walk < best {
                best = at + walk
                bestStation = station
            }
        }

        for origin in origins where departAt + origin.walkMinutes < earliest[origin.station, default: .max] {
            earliest[origin.station] = departAt + origin.walkMinutes
            reached[origin.station] = .start(origin)
        }

        var index = firstDeparture(atOrAfter: departAt)
        while index < connections.count {
            let connection = connections[index]
            defer { index += 1 }
            if connection.departure > best { break }  // nothing later can arrive earlier

            let entered: Int
            if let known = tripEntered[connection.trip] {
                entered = known
            } else {
                guard let at = earliest[connection.from] else { continue }
                let ready = at + (arrivedByRide.contains(connection.from) ? minChange : 0)
                guard ready <= connection.departure else { continue }
                entered = index
                tripEntered[connection.trip] = index
            }

            guard connection.arrival < earliest[connection.to, default: .max] else { continue }
            earliest[connection.to] = connection.arrival
            reached[connection.to] = .byRide(enter: entered, exit: index)
            arrivedByRide.insert(connection.to)
            offer(connection.to)
            for path in footpaths[connection.to] ?? [] {
                let time = connection.arrival + path.walkMinutes
                if time < earliest[path.station, default: .max] {
                    earliest[path.station] = time
                    reached[path.station] = .byWalk(from: connection.to, minutes: path.walkMinutes)
                    arrivedByRide.remove(path.station)
                    offer(path.station)
                }
            }
        }

        guard let last = bestStation, let egressWalk = egress[last],
              let (access, parts) = rebuild(from: last, reached: reached) else { return nil }
        guard case .ride = parts.first else { return nil }  // walking only is not a bus route
        return RouteResult(access: access, parts: parts, egress: Access(station: last, walkMinutes: egressWalk),
                           arrival: best)
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    /// Follows the pointers from the target back to the start; parts come out in travel order.
    private func rebuild(from target: Int, reached: [Int: Reached]) -> (Access, [RoutePart])? {
        var parts: [RoutePart] = []
        var station = target
        for _ in 0..<64 {
            switch reached[station] {
            case let .start(access)?:
                return (access, parts.reversed())
            case let .byRide(enter, exit)?:
                let first = connections[enter], final = connections[exit]
                parts.append(.ride(trip: first.trip, from: first.from, to: final.to,
                                   departure: first.departure, arrival: final.arrival))
                station = first.from
            case let .byWalk(from, minutes)?:
                parts.append(.transfer(from: from, to: station, minutes: minutes))
                station = from
            case nil:
                return nil
            }
        }
        return nil
    }

    private func firstDeparture(atOrAfter time: Int) -> Int {
        var low = 0, high = connections.count
        while low < high {
            let mid = (low + high) / 2
            if connections[mid].departure < time { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
