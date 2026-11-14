import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// Reads EFA-BW's departure monitor (`XML_DM_REQUEST`, rapidJSON). The JSON paths are listed in
/// `Tests/LiveCoreTests/Fixtures/README.md`, taken from recorded responses.
public enum EFAParser {
    private struct Feed: Decodable {
        struct Event: Decodable {
            struct Location: Decodable {
                struct Parent: Decodable { var id: String? }
                var id: String?
                var parent: Parent?
            }

            struct Transportation: Decodable {
                struct Product: Decodable { var `class`: Int? }
                struct Destination: Decodable { var name: String? }
                var number: String?
                var disassembledName: String?
                var product: Product?
                var destination: Destination?
            }

            var realtimeStatus: [String]?
            var isCancelled: Bool?
            var location: Location?
            var departureTimePlanned: String?
            var departureTimeEstimated: String?
            var transportation: Transportation?
        }

        var stopEvents: [Event]?
    }

    public static func parse(_ data: Data, stopGID: String) throws -> [UpstreamDeparture] {
        let feed: Feed
        do {
            feed = try JSONDecoder().decode(Feed.self, from: data)
        } catch {
            throw UpstreamError.unreadable(String(describing: error))
        }
        // A stop with no departures in the window answers without `stopEvents`.
        return (feed.stopEvents ?? []).compactMap { event in
            guard let transport = event.transportation,
                  let rawLine = transport.number ?? transport.disassembledName,
                  let planned = event.departureTimePlanned.flatMap(date) else { return nil }
            let status = event.realtimeStatus ?? []
            let platform = event.location?.id ?? event.location?.parent?.id ?? stopGID
            return UpstreamDeparture(
                platform: platform, line: rawLine.replacingOccurrences(of: " ", with: ""),
                destinationName: transport.destination?.name ?? "", planned: planned,
                realtime: event.departureTimeEstimated.flatMap(date),
                isCancelled: event.isCancelled == true || status.contains("TRIP_CANCELLED"),
                isCityBus: transport.product?.class == 5
            )
        }
    }

    private static func date(_ text: String) -> Date? { try? Date(text, strategy: .iso8601) }

    public static func url(stopGID: String, limit: Int) -> String {
        var parts = URLComponents(string: "https://www.efa-bw.de/nvbw/XML_DM_REQUEST")!
        parts.queryItems = [
            .init(name: "outputFormat", value: "rapidJSON"), .init(name: "type_dm", value: "stop"),
            .init(name: "mode", value: "direct"), .init(name: "useRealtime", value: "1"),
            .init(name: "depType", value: "stopEvents"), .init(name: "name_dm", value: stopGID),
            .init(name: "limit", value: String(limit)),
        ]
        return parts.url!.absoluteString
    }
}

/// Talks to EFA-BW. Never used on its own: the server wraps it in a `GuardedSource`.
public struct EFAClient: RealtimeSource {
    let http: HTTPClient
    let userAgent: String
    let timeout: TimeAmount
    let urlForStop: @Sendable (String, Int) -> String

    public init(http: HTTPClient, userAgent: String, timeoutSeconds: Int64 = 5,
                urlForStop: @escaping @Sendable (String, Int) -> String = EFAParser.url) {
        self.http = http
        self.userAgent = userAgent
        timeout = .seconds(timeoutSeconds)
        self.urlForStop = urlForStop
    }

    public func departures(stopGID: String, limit: Int) async throws -> [UpstreamDeparture] {
        var request = HTTPClientRequest(url: urlForStop(stopGID, limit))
        request.headers.add(name: "User-Agent", value: userAgent)
        request.headers.add(name: "Accept", value: "application/json")
        request.headers.add(name: "Accept-Encoding", value: "gzip")
        let response: HTTPClientResponse
        let body: ByteBuffer
        do {
            response = try await http.execute(request, timeout: timeout)
            body = try await response.body.collect(upTo: 4 << 20)
        } catch let error as HTTPClientError where error == .deadlineExceeded || error == .readTimeout
            || error == .connectTimeout {
            throw UpstreamError.timeout
        } catch {
            throw UpstreamError.transport(String(describing: error))
        }
        guard response.status == .ok else {
            let retry = response.headers.first(name: "Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            throw UpstreamError.status(Int(response.status.code), retryAfter: retry)
        }
        return try EFAParser.parse(Data(body.readableBytesView), stopGID: stopGID)
    }
}
