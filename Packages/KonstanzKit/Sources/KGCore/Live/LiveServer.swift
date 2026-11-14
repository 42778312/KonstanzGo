import Foundation
import KGLiveAPI

/// Where live delays come from when the KonstanzGo server is switched on: its URL, from the build setting
/// `KG_LIVE_URL`. On only when `KG_LIVE_ENABLED` is YES, or, in test builds, when the debug switch `live.server`
/// is on. Off, the app reads EFA-BW itself as before.
public struct LiveServerConfig: Sendable, Equatable {
    public static let switchKey = "live.server"
    public static let urlKey = "live.serverURL"

    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The configuration of this build, or nil when the server isn't used.
    public static func current(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
                               defaults: UserDefaults = .standard) -> LiveServerConfig? {
        var address = (info["KGLiveServerURL"] as? String) ?? ""
        var isOn = ((info["KGLiveServerEnabled"] as? String) ?? "").uppercased() == "YES"
        #if DEBUG
        if let override = defaults.string(forKey: urlKey), !override.isEmpty { address = override }
        if defaults.object(forKey: switchKey) != nil { isOn = defaults.bool(forKey: switchKey) }
        #endif
        guard isOn, !address.isEmpty, let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return nil }
        return LiveServerConfig(url: url)
    }
}

/// Talks to the KonstanzGo live server: the shared snapshot (with `If-None-Match`, so an unchanged one costs a 304)
/// and one stop's departures. 5 s timeout; the server never sees who is asking.
public actor LiveServerClient {
    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum Failure: Error, Equatable {
        case status(Int, retryAfter: TimeInterval?)
        case unreadable
    }

    let base: URL
    let send: Send
    private var etag: String?
    private var last: LiveSnapshot?

    public init(base: URL, send: @escaping Send = LiveServerClient.urlSession) {
        self.base = base
        self.send = send
    }

    /// The newest snapshot; the last one again when the server says nothing changed.
    public func snapshot() async throws -> LiveSnapshot {
        var request = Self.request(base.appending(path: "v1/live/snapshot"))
        if let etag, last != nil { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await send(request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304, let last { return last }
        try Self.check(http)
        guard let snapshot = try? JSONDecoder().decode(LiveSnapshot.self, from: data) else { throw Failure.unreadable }
        etag = http?.value(forHTTPHeaderField: "ETag")
        last = snapshot
        return snapshot
    }

    /// Live departures of a stop area ("de:08335:11918").
    public func departures(stopGID: String, limit: Int = 20) async throws -> StopDeparturesDTO {
        var url = base.appending(path: "v1/stops/\(stopGID)/departures")
        url.append(queryItems: [URLQueryItem(name: "limit", value: String(limit))])
        let (data, response) = try await send(Self.request(url))
        try Self.check(response as? HTTPURLResponse)
        guard let answer = try? JSONDecoder().decode(StopDeparturesDTO.self, from: data) else { throw Failure.unreadable }
        return answer
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func check(_ http: HTTPURLResponse?) throws {
        guard let http else { throw Failure.unreadable }
        guard http.statusCode == 200 else {
            throw Failure.status(http.statusCode,
                                 retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        }
    }

    public static let urlSession: Send = { request in try await URLSession.shared.data(for: request) }
}

/// A snapshot put onto the timetable: delays and cancellations by trip id, each with the time it was seen.
public struct LiveDelays: Sendable, Equatable {
    public var delays: [Int: Double] = [:]
    public var cancelled: Set<Int> = []
    public var seen: [Int: Date] = [:]
    public var upstream: UpstreamState
    /// When the server built the snapshot.
    public var generatedAt: Date
    /// Trips in the snapshot this timetable doesn't know (another timetable build): shown as scheduled.
    public var unknown = 0

    /// `keys` maps trip keys to trip ids for the service days running now.
    public init(_ snapshot: LiveSnapshot, keys: [String: Int]) {
        upstream = snapshot.upstream
        generatedAt = Date(timeIntervalSince1970: TimeInterval(snapshot.generatedAt))
        for trip in snapshot.trips {
            guard let id = keys[trip.k] else { unknown += 1; continue }
            delays[id] = Double(trip.d)
            seen[id] = Date(timeIntervalSince1970: TimeInterval(trip.t))
        }
        for key in snapshot.cancelled {
            guard let id = keys[key] else { unknown += 1; continue }
            cancelled.insert(id)
            seen[id] = generatedAt
        }
    }

    /// Whether live data is flowing: the server's source answers, and the snapshot is recent.
    public func isLive(at date: Date) -> Bool { upstream == .ok && date.timeIntervalSince(generatedAt) < 180 }
}

extension StopDeparturesDTO {
    /// The server's answer in the form the departure merge reads.
    public var events: [LiveEvent] {
        departures.map { departure in
            LiveEvent(line: departure.line.replacingOccurrences(of: " ", with: ""),
                      planned: Date(timeIntervalSince1970: TimeInterval(departure.planned)), platform: departure.platform,
                      delay: departure.realtime.map { $0 - departure.planned }, isCancelled: departure.cancelled)
        }
    }
}
