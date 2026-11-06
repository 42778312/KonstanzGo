import Foundation

/// What EFA-BW says about one bus at a stop right now.
public struct LiveEvent: Sendable, Hashable {
    public var line: String
    public var planned: Date
    public var platform: String?
    /// Seconds behind the timetable; nil when no vehicle reports for this bus.
    public var delay: Int?
    public var isCancelled: Bool

    public init(line: String, planned: Date, platform: String? = nil, delay: Int? = nil, isCancelled: Bool = false) {
        self.line = line
        self.planned = planned
        self.platform = platform
        self.delay = delay
        self.isCancelled = isCancelled
    }
}

/// Reads EFA-BW's departure monitor (`XML_DM_REQUEST`, rapidJSON) and puts it onto the timetable.
public enum EFADepartures {
    public static func url(stopArea: String, limit: Int = 40) -> URL? {
        var parts = URLComponents(string: "https://www.efa-bw.de/nvbw/XML_DM_REQUEST")
        parts?.queryItems = [
            .init(name: "outputFormat", value: "rapidJSON"), .init(name: "name_dm", value: stopArea),
            .init(name: "type_dm", value: "stop"), .init(name: "mode", value: "direct"),
            .init(name: "useRealtime", value: "1"), .init(name: "depType", value: "stopEvents"),
            .init(name: "limit", value: String(limit))
        ]
        return parts?.url
    }

    private struct Feed: Decodable {
        struct Event: Decodable {
            struct Location: Decodable { var id: String? }
            struct Transportation: Decodable { var number: String? }
            var realtimeStatus: [String]?
            var isCancelled: Bool?
            var location: Location?
            var departureTimePlanned: String?
            var departureTimeEstimated: String?
            var transportation: Transportation?
        }

        var stopEvents: [Event]?
    }

    public static func parse(_ data: Data) throws -> [LiveEvent] {
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard let events = feed.stopEvents else { throw URLError(.cannotParseResponse) }
        return events.compactMap { event in
            guard let number = event.transportation?.number,
                  let planned = event.departureTimePlanned.flatMap({ try? Date($0, strategy: .iso8601) }) else { return nil }
            let estimated = event.departureTimeEstimated.flatMap { try? Date($0, strategy: .iso8601) }
            let status = event.realtimeStatus ?? []
            return LiveEvent(line: number.replacingOccurrences(of: " ", with: ""), planned: planned,
                             platform: event.location?.id,
                             delay: estimated.map { Int($0.timeIntervalSince(planned)) },
                             isCancelled: event.isCancelled == true || status.contains("TRIP_CANCELLED")
                                 || status.contains("STOP_CANCELLED"))
        }
    }

    /// The timetable's departures with what the events say. Matched on line and time, on the platform too when
    /// two buses of a line leave in the same minute. Buses without a report stay `.scheduled`.
    public static func merge(_ departures: [Departure], with events: [LiveEvent]) -> [Departure] {
        var byMinute: [String: [LiveEvent]] = [:]
        for event in events { byMinute[key(event.line, event.planned), default: []].append(event) }
        return departures.map { departure in
            guard departure.status != .stopClosed,
                  let candidates = byMinute[key(departure.line.name, departure.scheduled)] else { return departure }
            let event = candidates.first { $0.platform != nil && $0.platform == departure.platform.gtfsID }
                ?? (candidates.count == 1 ? candidates[0] : nil)
            guard let event else { return departure }
            var merged = departure
            if event.isCancelled {
                merged.status = .cancelled
            } else if let delay = event.delay {
                merged.status = .live(delayMinutes: max(0, Int((Double(delay) / 60).rounded())))
                merged.delaySeconds = max(0, delay)
            }
            return merged
        }
    }

    private static func key(_ line: String, _ date: Date) -> String {
        "\(line)|\(Int(date.timeIntervalSince1970 / 60))"
    }
}
