import Foundation

/// A stop area with one name, "Sternenplatz". Buses stop at its platforms.
public struct Station: Sendable, Hashable, Identifiable, Codable {
    public var id: Int
    public var name: String
    /// Name without the town, for tight spaces.
    public var shortName: String
    public var coordinate: Coordinate

    public init(id: Int, name: String, shortName: String, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.coordinate = coordinate
    }
}

/// One boarding point of a station ("Steig A").
public struct Platform: Sendable, Hashable, Identifiable, Codable {
    public var id: Int
    public var stationID: Int
    /// The platform letter or number shown on the sign; nil when the timetable has none.
    public var code: String?
    public var coordinate: Coordinate
    /// Which way buses leave from here, from the city's stop register; nil when unknown.
    public var direction: String?

    public init(id: Int, stationID: Int, code: String?, coordinate: Coordinate, direction: String?) {
        self.id = id
        self.stationID = stationID
        self.code = code
        self.coordinate = coordinate
        self.direction = direction
    }
}

/// What drives a line, for its top speed on the map.
public enum VehicleMode: String, Sendable, Hashable, Codable {
    case bus, train, ferry

    /// GTFS route_type: trams (0, the S-Bahn here), metro (1) and rail (2) are trains; 4 is a ferry.
    public init(routeType: Int) {
        switch routeType {
        case 0, 1, 2: self = .train
        case 4: self = .ferry
        default: self = .bus
        }
    }

    /// Fastest it drives, km/h. The motion never goes past it unless the timetable itself asks for more.
    public var topSpeedKmh: Double {
        switch self {
        case .bus: 80
        case .train: 160
        case .ferry: 40
        }
    }
}

/// A bus line or ferry, "9A".
public struct Line: Sendable, Hashable, Identifiable, Codable {
    public var id: Int
    /// The number on the badge.
    public var name: String
    public var longName: String
    /// One of the Konstanz city lines (others are regional buses passing through).
    public var isCity: Bool
    public var mode: VehicleMode
    /// Who runs it, the feed's agency ("vhb-SW-KN" Stadtwerke Konstanz, "sbb-801" a Swiss operator).
    public var agency: String?

    public init(id: Int, name: String, longName: String, isCity: Bool, mode: VehicleMode = .bus,
                agency: String? = nil) {
        self.id = id
        self.name = name
        self.longName = longName
        self.isCity = isCity
        self.mode = mode
        self.agency = agency
    }

    /// The Swiss buses over the border to Kreuzlingen (908, 925, EV1–EV4): yellow on the map, like there.
    public var isKreuzlingenBus: Bool {
        mode == .bus && (agency?.hasPrefix("sbb-") ?? false)
    }
}

/// What the app knows about when a bus really comes. Today the app has only the timetable, so every
/// departure is `.scheduled`; `.live` exists for a future realtime feed. Only `.live` may be shown green.
public enum DepartureStatus: Sendable, Hashable, Codable {
    case scheduled
    case live(delayMinutes: Int)

    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    public var delayMinutes: Int {
        if case let .live(delay) = self { return delay }
        return 0
    }
}

/// A bus leaving a station: the row in "In deiner Nähe" and on the stop screen.
public struct Departure: Sendable, Hashable, Identifiable {
    public var tripID: Int
    public var line: Line
    /// Where the bus goes, as shown on it.
    public var headsign: String
    public var platform: Platform
    /// Timetable time.
    public var scheduled: Date
    public var status: DepartureStatus

    public var id: String { "\(tripID)@\(platform.id)@\(scheduled.timeIntervalSince1970)" }

    /// When the bus is expected: the timetable time plus any live delay.
    public var expected: Date { scheduled.addingTimeInterval(TimeInterval(status.delayMinutes * 60)) }

    public init(tripID: Int, line: Line, headsign: String, platform: Platform, scheduled: Date,
                status: DepartureStatus = .scheduled) {
        self.tripID = tripID
        self.line = line
        self.headsign = headsign
        self.platform = platform
        self.scheduled = scheduled
        self.status = status
    }
}

/// One stop of a trip, with its times (departure details, journey timeline).
public struct TripStop: Sendable, Hashable {
    public var station: Station
    public var platform: Platform
    public var arrival: Date
    public var departure: Date

    public init(station: Station, platform: Platform, arrival: Date, departure: Date) {
        self.station = station
        self.platform = platform
        self.arrival = arrival
        self.departure = departure
    }
}

/// One run of a line on one day with all its stops.
public struct Trip: Sendable, Hashable, Identifiable {
    public var id: Int
    public var line: Line
    public var headsign: String
    public var stops: [TripStop]
    /// The road the bus drives, for the map; empty when the timetable has no shape.
    public var shape: [Coordinate]

    public init(id: Int, line: Line, headsign: String, stops: [TripStop], shape: [Coordinate]) {
        self.id = id
        self.line = line
        self.headsign = headsign
        self.stops = stops
        self.shape = shape
    }
}
