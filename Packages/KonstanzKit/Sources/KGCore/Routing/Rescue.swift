import Foundation

/// What's known right now about the buses, from `LiveModel`.
public struct LiveState: Sendable, Hashable {
    /// Seconds late, per trip.
    public var delays: [Int: Double]
    public var cancelled: Set<Int>
    public var closures: StopClosures

    public init(delays: [Int: Double] = [:], cancelled: Set<Int> = [], closures: StopClosures = StopClosures()) {
        self.delays = delays
        self.cancelled = cancelled
        self.closures = closures
    }

    public func expectedStart(_ ride: RideLeg) -> Date { ride.start.addingTimeInterval(delays[ride.tripID] ?? 0) }
    public func expectedEnd(_ ride: RideLeg) -> Date { ride.end.addingTimeInterval(delays[ride.tripID] ?? 0) }

    /// When the journey really ends, with the last bus's delay.
    public func expectedEnd(_ journey: Journey) -> Date {
        journey.end.addingTimeInterval(journey.rides.last.flatMap { delays[$0.tripID] } ?? 0)
    }
}

/// Whether the journey still works.
public enum JourneyRisk: Sendable, Hashable {
    case fine
    /// The change still works, but only just.
    case tight(next: RideLeg, seconds: Int)
    /// The next bus leaves before the user can get to it.
    case missed(next: RideLeg, secondsShort: Int)
    case cancelled(RideLeg)
    /// The bus doesn't stop where the user gets on or off.
    case stopClosed(RideLeg, stop: String)

    /// The route no longer works as planned.
    public var isBroken: Bool {
        switch self {
        case .fine, .tight: false
        case .missed, .cancelled, .stopClosed: true
        }
    }
}

extension Journey {
    /// Checks the rides still to come against what's known. `location` catches a first bus the user can't
    /// walk to in time, or has already missed.
    public func risk(at now: Date, live: LiveState, location: Coordinate? = nil) -> JourneyRisk {
        let ahead = rides.filter { live.expectedEnd($0) > now }
        for ride in ahead {
            if live.cancelled.contains(ride.tripID) { return .cancelled(ride) }
            let boarded = live.expectedStart(ride) <= now
            for stop in boarded ? [ride.alighting] : [ride.boarding, ride.alighting]
            where live.closures.isClosed(station: stop.station.id, line: ride.line.name) {
                return .stopClosed(ride, stop: stop.station.shortName)
            }
        }
        if let first = ahead.first, first.tripID == rides.first?.tripID, let location,
           let short = shortfall(for: first, at: now, live: live, location: location) {
            return .missed(next: first, secondsShort: short)
        }
        var tight: JourneyRisk?
        var previous: RideLeg?
        var walking: TimeInterval = 0
        for leg in legs {
            switch leg {
            case let .walk(walk):
                walking += walk.end.timeIntervalSince(walk.start)
            case let .ride(ride):
                if let last = previous, live.expectedEnd(ride) > now {
                    let ready = live.expectedEnd(last).addingTimeInterval(walking)
                    let margin = Int(live.expectedStart(ride).timeIntervalSince(ready))
                    if margin < 0 { return .missed(next: ride, secondsShort: -margin) }
                    if margin < Self.tightSeconds, tight == nil, live.delays[last.tripID] != nil || live.delays[ride.tripID] != nil {
                        tight = .tight(next: ride, seconds: margin)
                    }
                }
                previous = ride
                walking = 0
            }
        }
        return tight ?? .fine
    }

    private static let tightSeconds = 90

    /// How many seconds too late the user is for the first bus, or nil when it's still possible.
    private func shortfall(for ride: RideLeg, at now: Date, live: LiveState, location: Coordinate) -> Int? {
        let leaves = live.expectedStart(ride)
        if leaves > now {
            let metres = Walking.estimatedMetres(from: location, to: ride.boarding.platform.coordinate)
            guard metres > 80 else { return nil }
            let short = now.addingTimeInterval(TimeInterval(Walking.minutes(forMetres: metres) * 60)).timeIntervalSince(leaves)
            return short > 60 ? Int(short) : nil
        }
        // It should be on its way: is the user anywhere along it? (A poor fix only brings a suggestion.)
        guard now.timeIntervalSince(leaves) > 60 else { return nil }
        let near = ride.stops.contains { $0.platform.coordinate.distance(to: location) < 500 }
            || ride.path.contains { $0.distance(to: location) < 300 }
        return near ? nil : Int(now.timeIntervalSince(leaves))
    }
}

/// Another way to the same target, from where the user is now.
public struct RescueOption: Sendable, Hashable, Identifiable {
    public var journey: Journey
    /// Stay on the current bus until here, then go on. Nil when not on a bus or staying to the planned stop.
    public var getOffAt: Station?
    /// Really arrives then, with known delays.
    public var arrival: Date
    /// Minutes later than the original journey would have arrived; negative when sooner.
    public var minutesLater: Int

    public var id: String { journey.id }
}

extension JourneyPlanner {
    /// Up to three other ways to the journey's end, soonest first, from the timetable and whatever live data
    /// is known, so it also works offline. When on a bus, every stop still ahead is tried as the place to get off.
    public func rescue(_ journey: Journey, at now: Date, live: LiveState, location: Coordinate? = nil,
                       limit: Int = 3) throws -> [RescueOption] {
        guard let target = journey.target else { return [] }
        let current = journey.rides.first { live.expectedStart($0) <= now && live.expectedEnd($0) > now }
        // Other buses than the ones this route counts on: it's another route that's asked for.
        let avoid = Set(journey.rides.map(\.tripID)).union(live.cancelled)
        var options: [RescueOption] = []
        func offer(_ legs: [Leg], getOff: Station?) {
            let candidate = Journey(legs: legs)
            guard !candidate.risk(at: now, live: live).isBroken else { return }
            let arrival = live.expectedEnd(candidate)
            options.append(RescueOption(journey: candidate, getOffAt: getOff, arrival: arrival,
                                        minutesLater: Int((arrival.timeIntervalSince(live.expectedEnd(journey)) / 60).rounded())))
        }
        if let current, !live.cancelled.contains(current.tripID) {
            let delay = live.delays[current.tripID] ?? 0
            for (index, stop) in current.stops.enumerated() where index > 0 {
                let getsThere = stop.arrival.addingTimeInterval(delay)
                guard getsThere >= now,
                      !live.closures.isClosed(station: stop.station.id, line: current.line.name) else { continue }
                let request = PlanRequest(from: Endpoint(name: stop.station.shortName, coordinate: stop.station.coordinate),
                                          to: target, time: getsThere)
                let head = Self.ride(current, through: index)
                for plan in try plan(request, avoiding: avoid) {
                    offer([.ride(head)] + plan.legs, getOff: stop.station)
                }
            }
        } else {
            let from = location.map { Endpoint(name: "", coordinate: $0) } ?? journey.nextPoint(at: now, live: live)
            for plan in try plan(PlanRequest(from: from, to: target, time: now), avoiding: avoid) {
                offer(plan.legs, getOff: nil)
            }
        }
        return Self.best(options, limit: limit)
    }

    /// One option per set of buses, soonest first, fewest changes on a tie.
    private static func best(_ options: [RescueOption], limit: Int) -> [RescueOption] {
        let sorted = options.sorted {
            ($0.arrival, $0.journey.transfers, $0.journey.walkingMinutes)
                < ($1.arrival, $1.journey.transfers, $1.journey.walkingMinutes)
        }
        var seen: Set<[Int]> = []
        var kept: [RescueOption] = []
        for option in sorted where seen.insert(option.journey.rides.dropFirst(option.getOffAt == nil ? 0 : 1).map(\.tripID)).inserted {
            kept.append(option)
        }
        return Array(kept.prefix(limit))
    }

    /// The ride cut short at a later stop, with its piece of the route line.
    private static func ride(_ ride: RideLeg, through index: Int) -> RideLeg {
        var cut = ride
        cut.stops = Array(ride.stops[...index])
        cut.path = slice(ride.path, along: cut.stops.map(\.platform.coordinate))
        return cut
    }
}

extension Journey {
    /// Whether the route starts where the user is. If they planned it from somewhere else, their position says
    /// nothing about it: a route from Sternenplatz planned at home is still a route from Sternenplatz.
    public func startsNear(_ location: Coordinate?) -> Bool {
        guard let location else { return false }
        let first: Coordinate? = switch legs.first {
        case let .walk(walk): walk.path.first
        case let .ride(ride): ride.boarding.platform.coordinate
        case nil: nil
        }
        return first.map { $0.distance(to: location) < 150 } ?? false
    }

    /// Where the journey ends.
    var target: Endpoint? {
        switch legs.last {
        case let .walk(walk):
            walk.path.last.map { Endpoint(name: walk.destinationName, coordinate: $0) }
        case let .ride(ride):
            Endpoint(name: ride.alighting.station.shortName, coordinate: ride.alighting.station.coordinate)
        case nil:
            nil
        }
    }

    /// Without a position: the stop the user is at or heading to.
    func nextPoint(at now: Date, live: LiveState) -> Endpoint {
        let finished = rides.last { live.expectedEnd($0) <= now }
        let stop = finished?.alighting ?? rides.first { live.expectedStart($0) > now }?.boarding ?? rides.first?.boarding
        if let stop { return Endpoint(name: stop.station.shortName, coordinate: stop.station.coordinate) }
        let point = walks.first?.path.first ?? Coordinate(latitude: 0, longitude: 0)
        return Endpoint(name: walks.first?.destinationName ?? "", coordinate: point)
    }
}
