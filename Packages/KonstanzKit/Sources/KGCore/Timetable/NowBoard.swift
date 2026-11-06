import Foundation

/// How to reach a bus on foot.
public enum LeaveAdvice: Sendable, Hashable {
    /// Time to spare before setting off.
    case leaveIn(minutes: Int)
    case leaveNow
    /// Only at a brisk walk.
    case hurry
    case tooLate

    /// A minute in hand, so a short wait beats a missed bus; a brisk walk takes about three quarters of the time.
    public static func forBus(leaving departure: Date, walkMinutes: Int, now: Date) -> LeaveAdvice {
        let walk = TimeInterval(walkMinutes * 60)
        let spare = departure.timeIntervalSince(now) - walk
        if spare >= 120 { return .leaveIn(minutes: Int((spare - 60) / 60)) }
        if spare >= 30 { return .leaveNow }
        if departure.timeIntervalSince(now) >= walk * 0.75 { return .hurry }
        return .tooLate
    }
}

/// A stop near the user with its timetable, before anything live is known.
public struct NowCandidate: Sendable, Hashable {
    public var station: Station
    /// Nil when the user's position is unknown.
    public var walkMinutes: Int?
    public var isSaved: Bool
    public var departures: [Departure]

    public init(station: Station, walkMinutes: Int?, isSaved: Bool, departures: [Departure]) {
        self.station = station
        self.walkMinutes = walkMinutes
        self.isSaved = isSaved
        self.departures = departures
    }
}

/// One line of the Jetzt card: the next bus the user can still catch on a line and direction.
public struct NowRow: Sendable, Hashable, Identifiable {
    public var departure: Departure
    /// Nil without a position, or when the stop is right here.
    public var advice: LeaveAdvice?

    public var id: String { departure.id }
}

public struct NowStop: Sendable, Hashable, Identifiable {
    public var station: Station
    public var walkMinutes: Int?
    public var isSaved: Bool
    public var rows: [NowRow]

    public var id: Int { station.id }
}

/// What the Jetzt card shows: the answer to "when's my bus?", without a tap.
public enum NowBoard {
    public static let maxStops = 2
    public static let rowsPerStop = 2
    /// A saved stop counts as "here" from this close; further away, the nearest stops say more.
    public static let savedNearbyMetres = 800.0
    /// Stops looked at, to find two with buses coming.
    static let candidates = 8
    /// How far ahead counts as "next".
    static let hoursAhead = 3

    /// The stops to consider, best first: saved ones nearby, then the nearest. Without a position, saved stops only.
    public static func candidates(in transit: some TransitService, near point: Coordinate?, saved: [Int], at date: Date,
                                  walker: WalkRouter? = nil) -> [NowCandidate] {
        var chosen: [(station: Station, isSaved: Bool)] = []
        let savedStations = saved.compactMap { transit.station(id: $0) }
        if let point {
            for station in savedStations where station.coordinate.distance(to: point) <= savedNearbyMetres {
                chosen.append((station, true))
            }
            for (station, _) in transit.stations(near: point, within: 1_500, limit: candidates)
            where !chosen.contains(where: { $0.station.id == station.id }) {
                chosen.append((station, savedStations.contains { $0.id == station.id }))
            }
        } else {
            chosen = savedStations.map { ($0, true) }
        }
        return chosen.prefix(candidates).enumerated().map { index, item in
            var walk: Int?
            if let point {
                // Street routes only for the likely winners, to keep this quick.
                let metres = index < 4 ? walker?.route(from: point, to: item.station.coordinate)?.metres : nil
                walk = Walking.minutes(forMetres: metres ?? Walking.estimatedMetres(from: point, to: item.station.coordinate))
            }
            let late = date.addingTimeInterval(-lateWindow)
            let horizon = date.addingTimeInterval(TimeInterval(hoursAhead * 3600))
            let departures = ((try? transit.departures(at: item.station.id, from: late, limit: 40)) ?? []).filter { $0.scheduled <= horizon }
            return NowCandidate(station: item.station, walkMinutes: walk, isSaved: item.isSaved, departures: departures)
        }
    }

    /// From a little before now: a late bus still counts when its timetable minute has passed.
    static let lateWindow: TimeInterval = 30 * 60

    /// Stops this much further than the nearest aren't preferred for having a sooner bus.
    static let similarWalkMinutes = 5

    /// Turns candidates, with whatever live is known, into the card: up to two stops with buses to catch. Saved
    /// stops first; then, among stops about as near, the one whose bus comes soonest.
    public static func stops(from candidates: [NowCandidate], now: Date) -> [NowStop] {
        let all = candidates.compactMap { candidate -> NowStop? in
            let rows = rows(candidate, now: now)
            return rows.isEmpty ? nil : NowStop(station: candidate.station, walkMinutes: candidate.walkMinutes,
                                                isSaved: candidate.isSaved, rows: rows)
        }
        let nearest = all.compactMap(\.walkMinutes).min() ?? 0
        func rank(_ stop: NowStop) -> (Int, Int, Date) {
            let tooFar = (stop.walkMinutes ?? 0) > nearest + similarWalkMinutes
            return (stop.isSaved ? 0 : 1, tooFar ? 1 : 0, stop.rows.first?.departure.expected ?? .distantFuture)
        }
        return Array(all.enumerated().sorted { lhs, rhs in
            let (left, right) = (rank(lhs.element), rank(rhs.element))
            return (left.0, left.1, left.2, lhs.offset) < (right.0, right.1, right.2, rhs.offset)
        }.prefix(maxStops).map(\.element))
    }

    private static func rows(_ candidate: NowCandidate, now: Date) -> [NowRow] {
        let walk = candidate.walkMinutes
        var seen = Set<String>()
        var rows: [NowRow] = []
        for departure in Departure.upcoming(candidate.departures, from: now, limit: 40) {
            guard departure.status != .cancelled, departure.status != .stopClosed else { continue }
            let advice = walk.flatMap { $0 > 1 ? LeaveAdvice.forBus(leaving: departure.expected, walkMinutes: $0, now: now) : nil }
            if advice == .tooLate { continue }
            guard seen.insert("\(departure.line.id)|\(departure.headsign)").inserted else { continue }
            rows.append(NowRow(departure: departure, advice: advice))
            if rows.count == rowsPerStop { break }
        }
        return rows
    }
}
