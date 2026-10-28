import Foundation

/// What to do at the start of a walking step; the icon in the directions.
public enum Maneuver: String, Sendable, Hashable, Codable, CaseIterable {
    case depart, straight, slightLeft, slightRight, left, right, sharpLeft, sharpRight, uTurn, stairs, cross, arrive
}

/// What kind of way a walking step follows (values as in `konstanz-walk.bin`).
public enum WayKind: UInt8, Sendable, Hashable, Codable {
    case street = 0, footpath = 1, steps = 2, pedestrian = 3, crossing = 4
}

/// One step of walking directions: "Rechts in die Bahnhofstraße · 120 m". The screen turns it into words.
public struct WalkStep: Sendable, Hashable {
    public var maneuver: Maneuver
    /// Street walked along after the turn; nil for unnamed paths.
    public var street: String?
    /// The kind of way, for unnamed paths ("über die Treppe", "durch die Fußgängerzone").
    public var way: WayKind
    public var onBridge: Bool
    /// Rounded for reading: 5 m steps under 100 m, then 10 m steps. 0 for the arrival.
    public var metres: Int
    /// Where the step starts.
    public var start: Coordinate
    /// Compass direction of the first metres, for the first step ("Richtung Norden").
    public var heading: Double

    public init(maneuver: Maneuver, street: String?, way: WayKind = .street, onBridge: Bool = false,
                metres: Int, start: Coordinate, heading: Double = 0) {
        self.maneuver = maneuver
        self.street = street
        self.way = way
        self.onBridge = onBridge
        self.metres = metres
        self.start = start
        self.heading = heading
    }
}

public struct WalkLeg: Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var metres: Int
    /// Where the walk ends: a station name or the target's name.
    public var destinationName: String
    public var steps: [WalkStep]
    public var path: [Coordinate]

    public init(start: Date, end: Date, metres: Int, destinationName: String,
                steps: [WalkStep] = [], path: [Coordinate] = []) {
        self.start = start
        self.end = end
        self.metres = metres
        self.destinationName = destinationName
        self.steps = steps
        self.path = path
    }
}

public struct RideLeg: Sendable, Hashable {
    public var tripID: Int
    public var line: Line
    public var headsign: String
    /// Where you get on, then every stop up to and including where you get off.
    public var stops: [TripStop]
    public var status: DepartureStatus
    /// The part of the trip's shape that is ridden.
    public var path: [Coordinate]

    public init(tripID: Int, line: Line, headsign: String, stops: [TripStop],
                status: DepartureStatus = .scheduled, path: [Coordinate] = []) {
        precondition(stops.count >= 2, "a ride needs a boarding and an alighting stop")
        self.tripID = tripID
        self.line = line
        self.headsign = headsign
        self.stops = stops
        self.status = status
        self.path = path
    }

    public var boarding: TripStop { stops[0] }
    public var alighting: TripStop { stops[stops.count - 1] }
    public var start: Date { boarding.departure }
    public var end: Date { alighting.arrival }
}

public enum Leg: Sendable, Hashable {
    case walk(WalkLeg)
    case ride(RideLeg)

    public var start: Date {
        switch self {
        case let .walk(walk): walk.start
        case let .ride(ride): ride.start
        }
    }

    public var end: Date {
        switch self {
        case let .walk(walk): walk.end
        case let .ride(ride): ride.end
        }
    }

    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// A way from A to B: walking and riding legs in order.
public struct Journey: Sendable, Hashable, Identifiable {
    public var legs: [Leg]

    public init(legs: [Leg]) {
        precondition(!legs.isEmpty, "a journey has at least one leg")
        self.legs = legs
    }

    public var id: String {
        legs.map { leg in
            switch leg {
            case let .walk(walk): "w\(Int(walk.start.timeIntervalSince1970))"
            case let .ride(ride): "r\(ride.tripID)"
            }
        }.joined(separator: "-")
    }

    public var start: Date { legs[0].start }
    public var end: Date { legs[legs.count - 1].end }
    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }

    public var rides: [RideLeg] {
        legs.compactMap { if case let .ride(ride) = $0 { ride } else { nil } }
    }

    public var walks: [WalkLeg] {
        legs.compactMap { if case let .walk(walk) = $0 { walk } else { nil } }
    }

    public var transfers: Int { max(0, rides.count - 1) }
    public var walkingMinutes: Int { walks.reduce(0) { $0 + Leg.walk($1).minutes } }
    public var walkingMetres: Int { walks.reduce(0) { $0 + $1.metres } }
    public var firstRide: RideLeg? { rides.first }
}
