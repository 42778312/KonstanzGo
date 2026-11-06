import Foundation
import Testing
@testable import KGCore

/// Against the real bundled timetable and answers recorded from EFA-BW on 5 Nov 2026.
@Suite("Live data", .serialized)
struct LiveTests {
    let store: TimetableStore
    let clock = ServiceClock()
    static let waterPipe = """
    {"type":"stopInfo","id":"ems-1014982","version":3,"timestamps":{"validity":[{"from":"2026-11-05T09:00:00Z",\
    "to":"2026-11-07T08:00:00Z"}]},"infoLinks":[{"content":"<div>Aufgrund eines Wasserrohrbruchs, k&ouml;nnen die \
    Haltestellen Br&uuml;elstr. und Schulthai&szlig;str. bis voraussichtlich Samstag, 07.11.2026 09:00 Uhr nicht \
    angefahren werden. Bitte nutzen Sie die Haltestelle D&ouml;belestr. oder Gartenstra&szlig;e.</div>"}],\
    "affected":{"lines":[{"number":"1","operator":{"id":"SW-KN"}},{"number":"5","operator":{"id":"SW-KN"}},\
    {"number":"9","operator":{"id":"SW-KN"}}],"stops":[{"id":"de:08335:11821"},{"id":"de:08335:11905"}]}}
    """
    static let line6 = """
    {"type":"lineInfo","id":"ems-1014946","version":1,"timestamps":{"validity":[{"from":"2026-11-02T03:00:00Z",\
    "to":"2027-07-31T22:00:00Z"}]},"infoLinks":[{"content":"Baustelle bis 31.7.2027."}],\
    "affected":{"lines":[{"number":"6","operator":{"id":"SW-KN"}}]}}
    """
    static let train = """
    {"type":"lineInfo","id":"VVS-ems-28676","version":1,"timestamps":{"validity":[{"from":"2026-12-05T22:00:00Z",\
    "to":"2026-12-05T23:40:00Z"}]},"infoLinks":[{"content":"Zug f&auml;hrt fr&uuml;her."}],\
    "affected":{"lines":[{"number":"RE4","operator":{"id":"00"}}]}}
    """
    static let lift = """
    {"type":"stopInfo","id":"lift","timestamps":{"validity":[{"from":"2026-11-01T00:00:00Z","to":"2026-12-01T00:00:00Z"}]},\
    "infoLinks":[{"content":"Der Aufzug ist gesperrt."}],"affected":{"stops":[{"id":"de:08335:11905"}]}}
    """

    static func feed(_ infos: String...) -> Data {
        Data(#"{"infos":{"current":[\#(infos.joined(separator: ","))]}}"#.utf8)
    }

    init() throws {
        store = try TimetableStore(url: repoData.timetable)
    }

    func at(_ yyyymmdd: Int, _ hour: Int, _ minute: Int) -> Date {
        clock.date(ServiceDay(yyyymmdd: yyyymmdd), minutes: hour * 60 + minute)
    }

    func station(_ name: String) throws -> Station {
        try #require(store.stations.first { $0.shortName == name })
    }

    func waterPipeNotice() throws -> ServiceNotice {
        try #require(try EFANotices.parse(Self.feed(Self.waterPipe), store: store).first)
    }

    // MARK: Reading the feed

    @Test("a closure names its stops, lines, end and the operator's alternatives")
    func readsAClosure() throws {
        let notice = try waterPipeNotice()
        #expect(notice.closesStops)
        #expect(notice.lines == ["1", "5", "9"])
        #expect(Set(notice.stations) == [try station("Brüelstraße").id, try station("Schulthaißstraße").id])
        #expect(notice.alternatives == [try station("Döbelestraße").id, try station("Gartenstraße").id])
        #expect(notice.text.hasPrefix("Aufgrund eines Wasserrohrbruchs, können"))
        #expect(notice.isActive(at: at(20261106, 12, 0)))
        #expect(!notice.isActive(at: at(20261107, 9, 0)))
        #expect(!notice.isActive(at: at(20261105, 9, 0)))
    }

    @Test("a closure without advice suggests the nearest open stops")
    func nearestAlternatives() throws {
        let plain = Self.waterPipe.replacingOccurrences(of: " Bitte nutzen Sie die Haltestelle D&ouml;belestr. oder Gartenstra&szlig;e.", with: "")
        let notice = try #require(try EFANotices.parse(Self.feed(plain), store: store).first)
        #expect(notice.alternatives.count == 2)
        #expect(!notice.alternatives.contains { notice.stations.contains($0) })
    }

    @Test("other operators' lines are left out; a line notice is listed but closes nothing")
    func filters() throws {
        let notices = try EFANotices.parse(Self.feed(Self.line6, Self.train), store: store)
        #expect(notices.map(\.id) == ["ems-1014946"])
        #expect(notices[0].closesStops == false)
    }

    @Test("a broken lift doesn't close the stop")
    func liftIsNotAClosure() throws {
        let notice = try #require(try EFANotices.parse(Self.feed(Self.lift), store: store).first)
        #expect(!notice.closesStops)
        #expect(notice.alternatives.isEmpty)
    }

    @Test("a broken answer throws, so the kept notices stay")
    func brokenAnswer() {
        #expect(throws: (any Error).self) { try EFANotices.parse(Data("<html>".utf8), store: store) }
    }

    // MARK: Closures

    @Test("a closure is per line, and ends by itself")
    func closuresByLine() throws {
        let notice = try waterPipeNotice()
        let stop = try station("Brüelstraße").id
        let during = StopClosures(notices: [notice], at: at(20261106, 12, 0))
        #expect(during.isClosed(station: stop, line: "5"))
        #expect(!during.isClosed(station: stop, line: "2"))
        #expect(StopClosures(notices: [notice], at: at(20261108, 12, 0)).isEmpty)
    }

    @Test("routes avoid a closed stop while it's closed and use it again afterwards")
    func plannerAvoidsClosedStops() throws {
        let planner = try JourneyPlanner(store: store, url: repoData.timetable)
        let closed = try station("Schulthaißstraße")
        let start = try station("Sternenplatz")
        func alights(_ time: Date) throws -> Bool {
            let request = PlanRequest(from: Endpoint(name: start.shortName, coordinate: start.coordinate),
                                      to: Endpoint(name: closed.shortName, coordinate: closed.coordinate), time: time)
            return try planner.plan(request).flatMap(\.rides).contains { ride in
                ride.alighting.station.id == closed.id && ride.line.name == "5"
            }
        }
        let during = at(20261106, 12, 0), after = at(20261109, 12, 0)
        #expect(try alights(during), "the timetable alone stops there")
        planner.update(notices: [try waterPipeNotice()])
        #expect(try !alights(during))
        #expect(try alights(after))
    }

    @Test("a closed stop's own departures on the named lines are marked")
    func departuresMarked() throws {
        let transit = try OfflineTransit(data: repoData)
        let stop = try station("Schulthaißstraße").id
        transit.update(notices: [try waterPipeNotice()])
        let during = try transit.departures(at: stop, from: at(20261106, 12, 0), limit: 10)
        #expect(!during.isEmpty)
        for departure in during {
            #expect((departure.status == .stopClosed) == ["1", "5", "9"].contains(departure.line.name))
        }
        let later = try transit.departures(at: stop, from: at(20261109, 12, 0), limit: 10)
        #expect(later.allSatisfy { $0.status == .scheduled })
    }

    // MARK: Delays

    @Test("EFA's departure monitor is read")
    func readsDepartures() throws {
        let data = Data("""
        {"stopEvents":[{"realtimeStatus":["MONITORED"],"location":{"id":"de:08335:6554:10:1"},\
        "departureTimePlanned":"2026-11-05T18:22:00Z","departureTimeEstimated":"2026-11-05T18:26:06Z",\
        "transportation":{"number":"2"}},\
        {"location":{"id":"x"},"departureTimePlanned":"2026-11-05T18:23:00Z","transportation":{"number":"S 6"}},\
        {"realtimeStatus":["TRIP_CANCELLED"],"departureTimePlanned":"2026-11-05T18:24:00Z","transportation":{"number":"9"}}]}
        """.utf8)
        let events = try EFADepartures.parse(data)
        #expect(events.count == 3)
        #expect(events[0].delay == 246)
        #expect(events[1].line == "S6" && events[1].delay == nil)
        #expect(events[2].isCancelled)
    }

    @Test("reports land on the matching bus; others stay timetable times")
    func merges() throws {
        let from = at(20261105, 12, 0)
        let departures = try store.departures(at: 15, from: from, limit: 3)
        #expect(departures.count == 3)
        let late = LiveEvent(line: departures[0].line.name, planned: departures[0].scheduled,
                             platform: departures[0].platform.gtfsID, delay: 200)
        let gone = LiveEvent(line: departures[1].line.name, planned: departures[1].scheduled,
                             platform: departures[1].platform.gtfsID, isCancelled: true)
        let merged = EFADepartures.merge(departures, with: [late, gone])
        #expect(merged[0].status == .live(delayMinutes: 3))
        #expect(merged[0].expected == departures[0].scheduled.addingTimeInterval(180))
        #expect(merged[1].status == .cancelled)
        #expect(merged[2].status == .scheduled)
    }

    @Test("a late bus is drawn where it really is; a cancelled one not at all")
    func vehiclesFollowDelays() throws {
        let tracker = try VehicleTracker(store: store, url: repoData.timetable)
        let date = at(20261105, 12, 0)
        let bus = try #require(try tracker.positions(at: date, cityOnly: true).first)
        let earlier = try #require(try tracker.positions(at: date.addingTimeInterval(-120)).first { $0.tripID == bus.tripID })
        let late = try #require(try tracker.positions(at: date, cityOnly: true, delays: [bus.tripID: 120])
            .first { $0.tripID == bus.tripID })
        #expect(late.coordinate.distance(to: earlier.coordinate) < 1)
        #expect(!late.isEstimated)
        #expect(bus.isEstimated)
        let without = try tracker.positions(at: date, cityOnly: true, cancelled: [bus.tripID])
        #expect(!without.contains { $0.tripID == bus.tripID })
    }

    // MARK: Showing real times at once

    @MainActor
    func reporting(_ departures: [Departure], file: URL) -> LiveModel {
        let first = departures[0]
        let formatter = ISO8601DateFormatter()
        let planned = formatter.string(from: first.scheduled)
        let late = formatter.string(from: first.scheduled.addingTimeInterval(240))
        let answer = #"{"stopEvents":[{"location":{"id":"\#(first.platform.gtfsID ?? "")"},"departureTimePlanned":"\#(planned)","#
            + #""departureTimeEstimated":"\#(late)","transportation":{"number":"\#(first.line.name)"}}]}"#
        return LiveModel(store: store, file: file) { _ in Data(answer.utf8) }
    }

    func tempFile() -> URL { URL.temporaryDirectory.appending(path: "live-\(UUID().uuidString).json") }

    @MainActor
    @Test("a bus reported at one stop shows its real time at once everywhere, without asking")
    func instantFromAReport() async throws {
        let date = at(20261106, 12, 0)
        let departures = try store.departures(at: 15, from: date, limit: 5)
        let model = reporting(departures, file: tempFile())
        #expect(model.instant(departures, at: date)[0].status == .scheduled, "nothing known yet")
        _ = await model.live(departures, atStation: 15, at: date)
        let shown = model.instant(departures, at: date)
        #expect(shown[0].status == .live(delayMinutes: 4))
        #expect(shown[1].status == .scheduled)
    }

    @MainActor
    @Test("an old report stops counting")
    func instantExpires() async throws {
        let date = at(20261106, 12, 0)
        let departures = try store.departures(at: 15, from: date, limit: 5)
        let model = reporting(departures, file: tempFile())
        _ = await model.live(departures, atStation: 15, at: date)
        #expect(model.instant(departures, at: date.addingTimeInterval(4 * 60))[0].status == .live(delayMinutes: 4))
        #expect(model.instant(departures, at: date.addingTimeInterval(6 * 60))[0].status == .scheduled)
    }

    @MainActor
    @Test("reopened within minutes, the app remembers how late the buses are")
    func delaysSurviveARestart() async throws {
        let file = tempFile()
        var moved = try store.departures(at: 15, from: at(20261106, 12, 0), limit: 5)
        moved[0].scheduled = .now
        let model = reporting(moved, file: file)
        _ = await model.live(moved, atStation: 15)
        try await Task.sleep(for: .milliseconds(400))
        let again = LiveModel(store: store, file: file) { _ in throw URLError(.notConnectedToInternet) }
        #expect(again.instant(moved)[0].status == .live(delayMinutes: 4))
    }

    @MainActor
    @Test("two lists opening the same stop ask only once")
    func asksOnce() async throws {
        let date = at(20261106, 12, 0)
        let departures = try store.departures(at: 15, from: date, limit: 5)
        let calls = Calls()
        let model = LiveModel(store: store, file: tempFile()) { _ in
            await calls.add()
            try await Task.sleep(for: .milliseconds(50))
            return Data(#"{"stopEvents":[]}"#.utf8)
        }
        async let first = model.live(departures, atStation: 15, at: date)
        async let second = model.live(departures, atStation: 15, at: date)
        _ = await (first, second)
        #expect(await calls.count == 1)
    }

    // MARK: Keeping the last update

    @MainActor
    @Test("online it updates and keeps the notices; offline the last ones stay")
    func keepsNotices() async throws {
        let file = URL.temporaryDirectory.appending(path: "live-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let online = LiveModel(store: store, file: file) { _ in Self.feed(Self.waterPipe) }
        #expect(online.notices.isEmpty)
        await online.refresh()
        #expect(online.notices.count == 1)
        #expect(online.updated != nil)

        // Next start without internet.
        let applied = Applied()
        let offline = LiveModel(store: store, file: file, fetch: { _ in throw URLError(.notConnectedToInternet) },
                                onChange: { applied.set($0) })
        #expect(offline.notices.count == 1)
        #expect(applied.get().count == 1, "the planner hears about kept notices at launch")
        await offline.refresh()
        #expect(offline.notices.count == 1)

        // Back online, the operator has lifted it: it's gone at once.
        let lifted = LiveModel(store: store, file: file, fetch: { _ in Self.feed() }, onChange: { applied.set($0) })
        await lifted.refresh()
        #expect(lifted.notices.isEmpty)
        #expect(applied.get().isEmpty)
    }

    @MainActor
    @Test("asks at most every 5 minutes, sooner after a failure")
    func throttles() async throws {
        let file = URL.temporaryDirectory.appending(path: "live-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let calls = Calls()
        let model = LiveModel(store: store, file: file) { _ in
            await calls.add()
            throw URLError(.notConnectedToInternet)
        }
        let start = Date.now
        await model.refresh(at: start)
        await model.refresh(at: start.addingTimeInterval(30))
        #expect(await calls.count == 1)
        await model.refresh(at: start.addingTimeInterval(61))
        #expect(await calls.count == 2)
        await model.refresh(at: start.addingTimeInterval(62), force: true)
        #expect(await calls.count == 3)
    }

    @MainActor
    @Test("no answer means plain timetable times, never an old delay")
    func noAnswerNoDelay() async throws {
        let file = URL.temporaryDirectory.appending(path: "live-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let model = LiveModel(store: store, file: file) { _ in throw URLError(.notConnectedToInternet) }
        let departures = try store.departures(at: 15, from: at(20261105, 12, 0), limit: 3)
        let shown = await model.live(departures, atStation: 15, at: at(20261105, 12, 0))
        #expect(shown.allSatisfy { $0.status == .scheduled })
    }
}

private actor Calls {
    var count = 0
    func add() { count += 1 }
}

private final class Applied: @unchecked Sendable {
    private var value: [ServiceNotice] = []
    func set(_ new: [ServiceNotice]) { value = new }
    func get() -> [ServiceNotice] { value }
}
