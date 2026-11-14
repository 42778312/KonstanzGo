import Foundation

/// One departure as the live source reports it.
public struct UpstreamDeparture: Sendable, Hashable {
    /// The platform's DHID ("de:08335:6554:10:1"), or the stop area when the source names no platform.
    public var platform: String
    /// "1", "9A".
    public var line: String
    public var destinationName: String
    public var planned: Date
    /// Nil when no vehicle reports for this bus.
    public var realtime: Date?
    /// Only true when the source says so.
    public var isCancelled: Bool
    /// The source calls it a city bus (EFA-BW product class 5).
    public var isCityBus: Bool

    public init(platform: String, line: String, destinationName: String, planned: Date, realtime: Date?,
                isCancelled: Bool, isCityBus: Bool) {
        self.platform = platform
        self.line = line
        self.destinationName = destinationName
        self.planned = planned
        self.realtime = realtime
        self.isCancelled = isCancelled
        self.isCityBus = isCityBus
    }

    /// Seconds behind the timetable; nil when not monitored.
    public var delay: Int? { realtime.map { Int($0.timeIntervalSince(planned).rounded()) } }
}

/// Where live departures come from: EFA-BW now, NVBW's official feed later. The rest of the server only ever
/// sees a `GuardedSource` wrapped around one of these.
public protocol RealtimeSource: Sendable {
    /// Departures from a stop area ("de:08335:11918"), soonest first.
    func departures(stopGID: String, limit: Int) async throws -> [UpstreamDeparture]
}

public enum UpstreamError: Error, Equatable, CustomStringConvertible {
    /// The source answered with an error status; `retryAfter` in seconds when it said so.
    case status(Int, retryAfter: Int?)
    case timeout
    case transport(String)
    case unreadable(String)
    /// The rate limiter would have to wait too long.
    case denied
    /// The circuit breaker is open or backing off.
    case circuitOpen
    /// Live data is switched off.
    case disabled

    public var description: String {
        switch self {
        case let .status(code, retry): "HTTP \(code)" + (retry.map { ", retry after \($0) s" } ?? "")
        case .timeout: "timeout"
        case let .transport(message): "transport: \(message)"
        case let .unreadable(message): "unreadable response: \(message)"
        case .denied: "rate limit"
        case .circuitOpen: "circuit open"
        case .disabled: "disabled"
        }
    }

    /// The label for the `upstream_requests_total{status}` metric.
    var metricLabel: String {
        switch self {
        case let .status(code, _): String(code)
        case .timeout: "timeout"
        case .transport: "transport"
        case .unreadable: "unreadable"
        case .denied: "denied"
        case .circuitOpen: "circuit_open"
        case .disabled: "disabled"
        }
    }
}
