import Foundation

/// The version of the `/v1/` payloads. Fields are only ever added to v1; removing or renaming one means `/v2/`.
public enum LiveAPI {
    public static let version = 1
}

/// How the server's link to the live source is doing.
public enum UpstreamState: String, Codable, Sendable, Hashable {
    /// Fresh data is coming in.
    case ok
    /// The source is failing or not asked yet; the server serves what it still has.
    case degraded
    /// Live data is switched off on the server.
    case off

    /// An unknown value from a newer server reads as `.degraded`, never as an error.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UpstreamState(rawValue: raw) ?? .degraded
    }
}

/// The live delay of one trip. Short keys keep the snapshot small.
public struct TripLiveDTO: Codable, Sendable, Hashable {
    /// The trip key, see `TripKey`.
    public var k: String
    /// Delay in seconds; negative when early.
    public var d: Int
    /// When the delay was observed, seconds since 1970.
    public var t: Int

    public init(k: String, d: Int, t: Int) {
        self.k = k
        self.d = d
        self.t = t
    }
}

/// `GET /v1/live/snapshot`: the delays of every running city trip the server knows about.
public struct LiveSnapshot: Codable, Sendable, Hashable {
    public var v: Int
    /// Seconds since 1970.
    public var generatedAt: Int
    public var upstream: UpstreamState
    public var trips: [TripLiveDTO]
    /// Keys of trips the source marked cancelled.
    public var cancelled: [String]

    public init(v: Int = LiveAPI.version, generatedAt: Int, upstream: UpstreamState, trips: [TripLiveDTO],
                cancelled: [String]) {
        self.v = v
        self.generatedAt = generatedAt
        self.upstream = upstream
        self.trips = trips
        self.cancelled = cancelled
    }
}

/// One departure in `GET /v1/stops/{gid}/departures`.
public struct DepartureDTO: Codable, Sendable, Hashable {
    /// The trip key when the departure matched a trip of the timetable.
    public var k: String?
    public var line: String
    public var destination: String
    /// The platform's DHID ("de:08335:11918:0:2").
    public var platform: String?
    /// Seconds since 1970.
    public var planned: Int
    /// Seconds since 1970; nil when no vehicle reports for this bus.
    public var realtime: Int?
    public var cancelled: Bool

    public init(k: String?, line: String, destination: String, platform: String?, planned: Int, realtime: Int?,
                cancelled: Bool) {
        self.k = k
        self.line = line
        self.destination = destination
        self.platform = platform
        self.planned = planned
        self.realtime = realtime
        self.cancelled = cancelled
    }
}

/// `GET /v1/stops/{gid}/departures`.
public struct StopDeparturesDTO: Codable, Sendable, Hashable {
    public var v: Int
    public var generatedAt: Int
    public var upstream: UpstreamState
    /// The stop's gid ("de:08335:11918").
    public var stop: String
    public var departures: [DepartureDTO]

    public init(v: Int = LiveAPI.version, generatedAt: Int, upstream: UpstreamState, stop: String,
                departures: [DepartureDTO]) {
        self.v = v
        self.generatedAt = generatedAt
        self.upstream = upstream
        self.stop = stop
        self.departures = departures
    }
}

/// `GET /v1/health`.
public struct HealthDTO: Codable, Sendable, Hashable {
    public var status: String
    public var version: String
    public var feedVersion: String
    public var upstream: UpstreamState
    /// Nil before the first snapshot.
    public var snapshotAgeSeconds: Int?

    public init(status: String, version: String, feedVersion: String, upstream: UpstreamState, snapshotAgeSeconds: Int?) {
        self.status = status
        self.version = version
        self.feedVersion = feedVersion
        self.upstream = upstream
        self.snapshotAgeSeconds = snapshotAgeSeconds
    }
}

/// The natural name of a trip, the same on the app and the server even when they ship different timetable builds:
/// `<service date yyyyMMdd>|<line>|<first stop gid>|<planned first departure, minutes after service-day start>`,
/// for example `20261110|1|de:08335:6554|553`.
public enum TripKey {
    public static func make(serviceDate: Int, line: String, firstPlatform: String, firstDeparture: Int) -> String {
        "\(serviceDate)|\(line)|\(stopGID(of: firstPlatform))|\(firstDeparture)"
    }

    /// The stop area of a platform's DHID: its first three parts. "de:08335:11918:0:2" → "de:08335:11918",
    /// "de:08335:6554:1" → "de:08335:6554". Ids with fewer parts are returned unchanged.
    public static func stopGID(of dhid: String) -> String {
        dhid.split(separator: ":", omittingEmptySubsequences: false).prefix(3).joined(separator: ":")
    }

    /// Whether a string looks like a stop gid ("de:08335:11918"), so it is safe to pass on to the source.
    public static func isStopGID(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 2, parts[0].allSatisfy({ $0.isLetter && $0.isASCII }) else { return false }
        return parts.dropFirst().allSatisfy { !$0.isEmpty && $0.count <= 8 && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
}
