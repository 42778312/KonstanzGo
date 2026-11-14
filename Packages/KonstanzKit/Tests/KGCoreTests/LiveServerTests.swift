import Foundation
import KGLiveAPI
import Testing
@testable import KGCore

/// The app's side of the KonstanzGo live server (SERVER_PLAN.md S10), against the real bundled timetable.
@Suite("Live server", .serialized)
struct LiveServerTests {
    let store: TimetableStore
    let clock = ServiceClock()

    init() throws {
        store = try TimetableStore(url: repoData.timetable)
    }

    func at(_ yyyymmdd: Int, _ hour: Int, _ minute: Int) -> Date {
        clock.date(ServiceDay(yyyymmdd: yyyymmdd), minutes: hour * 60 + minute)
    }

    func tempFile() -> URL { URL.temporaryDirectory.appending(path: "live-server-\(UUID().uuidString).json") }

    /// A server that answers from a closure and remembers what it was asked.
    final class FakeServer: @unchecked Sendable {
        var requests: [URLRequest] = []
        var answer: (URLRequest) throws -> (Int, [String: String], Data)
        let lock = NSLock()

        init(answer: @escaping (URLRequest) throws -> (Int, [String: String], Data)) {
            self.answer = answer
        }

        var send: LiveServerClient.Send {
            { request in
                let (status, headers, body) = try self.lock.withLock {
                    self.requests.append(request)
                    return try self.answer(request)
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                               headerFields: headers)!
                return (body, response)
            }
        }
    }

    static func json(_ value: some Encodable) -> Data { try! JSONEncoder().encode(value) }

    // MARK: The flag

    @Test("off unless the build or the debug switch turns it on, and only with an address")
    func flag() throws {
        let defaults = try #require(UserDefaults(suiteName: "live-flag-\(UUID().uuidString)"))
        #expect(LiveServerConfig.current(info: [:], defaults: defaults) == nil)
        #expect(LiveServerConfig.current(info: ["KGLiveServerURL": "https://api.example.org", "KGLiveServerEnabled": "NO"],
                                         defaults: defaults) == nil)
        #expect(LiveServerConfig.current(info: ["KGLiveServerURL": "https://api.example.org", "KGLiveServerEnabled": "YES"],
                                         defaults: defaults)?.url.absoluteString == "https://api.example.org")
        #expect(LiveServerConfig.current(info: ["KGLiveServerURL": "", "KGLiveServerEnabled": "YES"], defaults: defaults) == nil)
        defaults.set(true, forKey: LiveServerConfig.switchKey)
        #expect(LiveServerConfig.current(info: ["KGLiveServerURL": "http://localhost:8080", "KGLiveServerEnabled": "NO"],
                                         defaults: defaults) != nil, "the debug switch turns it on in test builds")
    }

    // MARK: Trip keys

    /// The server named this trip on 14 Nov 2026 (a live run from the Mac); the app must find the same trip.
    @Test("the app names trips exactly like the server")
    func sameKeysAsTheServer() throws {
        let keys = try store.liveTripKeys(on: ServiceDay(yyyymmdd: 20261114))
        #expect(keys.count > 300)
        let id = try #require(keys["20261114|12|de:08335:11918|1121"])
        let trip = try #require(try store.trip(id: id, on: ServiceDay(yyyymmdd: 20261114)))
        #expect(trip.line.name == "12")
        #expect(keys.keys.allSatisfy { $0.split(separator: "|").count == 4 })
        // 9A and 9B (weekdays) stay apart: the server matched EFA-BW's "9" to them.
        let friday = try store.liveTripKeys(on: ServiceDay(yyyymmdd: 20261113))
        #expect(friday.keys.contains { $0.contains("|9A|") } && friday.keys.contains { $0.contains("|9B|") })
    }

    // MARK: The client

    @Test("an unchanged snapshot costs a 304 and keeps the last one")
    func etag() async throws {
        let snapshot = LiveSnapshot(generatedAt: 100, upstream: .ok, trips: [TripLiveDTO(k: "a", d: 60, t: 99)], cancelled: [])
        let server = FakeServer { request in
            request.value(forHTTPHeaderField: "If-None-Match") == "\"e1\"" ? (304, [:], Data())
                : (200, ["ETag": "\"e1\""], Self.json(snapshot))
        }
        let client = LiveServerClient(base: URL(string: "http://localhost:8080")!, send: server.send)
        #expect(try await client.snapshot() == snapshot)
        #expect(try await client.snapshot() == snapshot)
        #expect(server.requests.count == 2)
        #expect(server.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"e1\"")
        #expect(server.requests[0].url?.absoluteString == "http://localhost:8080/v1/live/snapshot")
        #expect(server.requests[0].timeoutInterval == 5)
    }

    @Test("stop departures by gid, and errors carry Retry-After")
    func departuresAndErrors() async throws {
        let answer = StopDeparturesDTO(generatedAt: 1, upstream: .ok, stop: "de:08335:11918", departures: [
            DepartureDTO(k: nil, line: "9", destination: "Uni", platform: "de:08335:11918:0:1", planned: 600, realtime: 720,
                         cancelled: false),
        ])
        let server = FakeServer { request in
            request.url?.path().contains("de:08335:11918") == true ? (200, [:], Self.json(answer))
                : (429, ["Retry-After": "30"], Data())
        }
        let client = LiveServerClient(base: URL(string: "http://localhost:8080")!, send: server.send)
        let found = try await client.departures(stopGID: "de:08335:11918", limit: 10)
        #expect(found.events.first?.delay == 120)
        #expect(server.requests[0].url?.query() == "limit=10")
        await #expect(throws: LiveServerClient.Failure.status(429, retryAfter: 30)) {
            try await client.departures(stopGID: "de:08335:11905")
        }
    }

    // MARK: Into the model

    @MainActor
    @Test("the snapshot's delays land on the trips, a dead source pauses live, off clears it")
    func snapshotIntoTheModel() async throws {
        let date = at(20261114, 18, 30)
        let keys = try store.liveTripKeys(on: ServiceDay(yyyymmdd: 20261114))
        let (key, trip) = try #require(keys.first { $0.key.hasPrefix("20261114|12|de:08335:11918|1121") })
        let observed = Int(date.timeIntervalSince1970) - 20
        var upstream = UpstreamState.ok
        let server = FakeServer { _ in
            (200, [:], Self.json(LiveSnapshot(generatedAt: Int(date.timeIntervalSince1970), upstream: upstream,
                                              trips: [TripLiveDTO(k: key, d: 180, t: observed),
                                                      TripLiveDTO(k: "20261114|99|de:1:1|1", d: 60, t: observed)],
                                              cancelled: [])))
        }
        let live = LiveModel(store: store, file: tempFile(), fetch: { _ in throw URLError(.cancelled) },
                             server: LiveServerClient(base: URL(string: "http://localhost:8080")!, send: server.send))
        #expect(live.usesServer)
        await live.warm(stations: [15, 99], at: date)
        #expect(live.tripDelays[trip] == 180)
        #expect(live.status(ofTrip: trip, at: date) == .live(delayMinutes: 3))
        #expect(!live.livePaused)
        // Asked again within 15 s: nothing goes out.
        await live.warm(stations: [15], at: date.addingTimeInterval(5))
        #expect(server.requests.count == 1)

        upstream = .degraded
        await live.refreshSnapshot(at: date.addingTimeInterval(20))
        #expect(live.livePaused)

        upstream = .off
        await live.refreshSnapshot(at: date.addingTimeInterval(40))
        #expect(live.tripDelays.isEmpty)
        #expect(live.status(ofTrip: trip, at: date.addingTimeInterval(40)) == .scheduled)
    }

    @MainActor
    @Test("no server for 3 minutes pauses live")
    func unreachable() async throws {
        let date = at(20261114, 18, 30)
        let server = FakeServer { _ in throw URLError(.notConnectedToInternet) }
        let live = LiveModel(store: store, file: tempFile(), fetch: { _ in throw URLError(.cancelled) },
                             server: LiveServerClient(base: URL(string: "http://localhost:8080")!, send: server.send))
        await live.refreshSnapshot(at: date)
        #expect(live.livePaused)
    }

    @MainActor
    @Test("a stop sheet reads the server, never EFA-BW")
    func stopSheetFromTheServer() async throws {
        let date = at(20261114, 12, 0)
        let station = try #require(store.stations.first { $0.name == "Konstanz Sternenplatz" })
        let departures = try store.departures(at: station.id, from: date, limit: 5)
        let first = try #require(departures.first)
        let answer = StopDeparturesDTO(generatedAt: 1, upstream: .ok, stop: "de:08335:11918", departures: [
            DepartureDTO(k: nil, line: first.line.name, destination: first.headsign, platform: first.platform.gtfsID,
                         planned: Int(first.scheduled.timeIntervalSince1970),
                         realtime: Int(first.scheduled.timeIntervalSince1970) + 240, cancelled: false),
        ])
        let server = FakeServer { _ in (200, [:], Self.json(answer)) }
        let live = LiveModel(store: store, file: tempFile(), fetch: { url in
            Issue.record("asked EFA-BW: \(url)")
            throw URLError(.cancelled)
        }, server: LiveServerClient(base: URL(string: "http://localhost:8080")!, send: server.send))
        let shown = await live.live(departures, atStation: station.id, at: date)
        #expect(shown.first?.status == .live(delayMinutes: 4))
        #expect(server.requests.first?.url?.path().hasSuffix("/v1/stops/de:08335:11918/departures") == true)
    }
}

extension LiveServerTests {
    @MainActor
    @Test("switched off on the server, a list that came in live goes back to the timetable and stays there")
    func offClearsListsToo() async throws {
        let date = at(20261114, 12, 0)
        let station = try #require(store.stations.first { $0.name == "Konstanz Sternenplatz" })
        var departures = try store.departures(at: station.id, from: date, limit: 5)
        departures[0].status = .live(delayMinutes: 4)
        departures[0].delaySeconds = 240
        let off = StopDeparturesDTO(generatedAt: 1, upstream: .off, stop: "de:08335:11918", departures: [])
        let server = FakeServer { request in
            request.url?.path().contains("snapshot") == true
                ? (200, [:], Self.json(LiveSnapshot(generatedAt: Int(date.timeIntervalSince1970), upstream: .off, trips: [],
                                                    cancelled: [])))
                : (200, [:], Self.json(off))
        }
        let live = LiveModel(store: store, file: tempFile(), fetch: { _ in throw URLError(.cancelled) },
                             server: LiveServerClient(base: URL(string: "http://localhost:8080")!, send: server.send))
        await live.refreshSnapshot(at: date)
        let shown = await live.live(departures, atStation: station.id, at: date)
        #expect(shown[0].status == .scheduled)
        #expect(live.tripDelays.isEmpty)
    }
}
