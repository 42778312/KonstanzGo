import Foundation
import KGLiveAPI
@testable import LiveCore
import Testing

@Suite struct MatchingTests {
    let timetable = Fixtures.timetable

    @Test func timetableLoadsCompletely() {
        #expect(timetable.stations.count == 142)
        #expect(timetable.trips.count == 3380)
        #expect(timetable.stopTimeCount == 33991)
        #expect(timetable.feedVersion == "20261011")
    }

    /// The golden test: at least 95 % of recorded city-bus departures find their trip.
    @Test func matchesAtLeast95PercentOfCityDepartures() {
        let matcher = TripMatcher(timetable: timetable)
        var city = 0, matched = 0
        var missed: [String] = []
        for response in Fixtures.responses {
            for departure in response.departures where matcher.isCity(departure) {
                city += 1
                if matcher.match(departure) != nil {
                    matched += 1
                } else {
                    missed.append("\(response.name) \(departure.line) \(departure.planned) \(departure.platform)")
                }
            }
        }
        #expect(city > 100)
        let rate = Double(matched) / Double(city)
        #expect(rate >= 0.95, "matched \(matched) of \(city): \(missed.prefix(10))")
        print("golden match rate: \(matched) of \(city) = \(Int(rate * 1000)) per mille; missed: \(missed)")
    }

    @Test func busAndTrainAreasOfBahnhofAreOneStation() throws {
        let bus = try #require(timetable.station(forPlatform: "de:08335:11882:0:1"))
        let train = try #require(timetable.station(forPlatform: "de:08335:6554:10:1"))
        #expect(bus == train)
        #expect(timetable.station(forPlatform: "de:08335:6554") == train)
        #expect(timetable.stations(forGID: "de:08335:11882") == [bus])
    }

    @Test func tripKeyIsNatural() throws {
        let matcher = TripMatcher(timetable: timetable)
        let sternenplatz = try #require(Fixtures.responses.first { $0.name.hasPrefix("dm_sternenplatz_20261113") })
        let match = try #require(matcher.match(sternenplatz.departures[0]))
        let parts = match.key.split(separator: "|")
        #expect(parts.count == 4)
        #expect(parts[0] == "20261113")
        #expect(parts[1] == "12")
        #expect(TripKey.isStopGID(String(parts[2])))
        #expect(Int(parts[3]) == match.trip.firstDeparture)
    }

    @Test func headsignBreaksTiesAndTiesStayUnmatched() {
        #expect(TripMatcher.fits(TripMatcher.words("Universität"), TripMatcher.words("Konstanz Universität")))
        #expect(!TripMatcher.fits(TripMatcher.words("Staad/Autofähre"), TripMatcher.words("Wollmatingen Rathaus")))
        #expect(TripMatcher.words("Schulthaißstraße") == ["schulthaissstrasse"])
    }

    @Test func unknownStationsAndLinesDontMatch() throws {
        let matcher = TripMatcher(timetable: timetable)
        let base = try #require(Fixtures.responses.first?.departures.first)
        var nowhere = base
        nowhere.platform = "de:99999:1:0:1"
        #expect(matcher.match(nowhere) == nil)
        var wrongLine = base
        wrongLine.line = "999"
        #expect(matcher.match(wrongLine) == nil)
    }

    @Test func serviceDayTimesAfterMidnight() {
        // 1510 on 27 Oct is 01:10 on 28 Oct.
        let date = BerlinTime.date(serviceDay: 20_261_027, minute: 1510)
        #expect(BerlinTime.wallClock(of: date) == (20_261_028, 70))
        let times = BerlinTime.serviceTimes(of: date)
        #expect(times.contains { $0 == (20_261_027, 1510) })
        #expect(times.contains { $0 == (20_261_028, 70) })
    }

    @Test func clockChangeSundays() {
        // 25 Oct 2026: clocks go back at 03:00 → 02:00. 29 Mar 2026: forward at 02:00 → 03:00.
        let autumnNoon = BerlinTime.date(serviceDay: 20_261_025, minute: 12 * 60)
        #expect(BerlinTime.wallClock(of: autumnNoon) == (20_261_025, 720))
        let springNoon = BerlinTime.date(serviceDay: 20_260_329, minute: 12 * 60)
        #expect(BerlinTime.wallClock(of: springNoon) == (20_260_329, 720))
        #expect(BerlinTime.previousDay(20_260_329) == 20_260_328)
        #expect(BerlinTime.previousDay(20_260_301) == 20_260_228)
        // A night bus on the autumn Saturday at 25:30 is 01:30 on Sunday.
        #expect(BerlinTime.wallClock(of: BerlinTime.date(serviceDay: 20_261_024, minute: 1530)) == (20_261_025, 90))
    }

    @Test func hubsCoverMostOfTheNetwork() {
        let hubs = timetable.hubs()
        #expect((12...15).contains(hubs.stations.count))
        #expect(hubs.coverage >= 0.9)
        #expect(hubs.stations.allSatisfy { TripKey.isStopGID($0.gid) })
    }
}

@Suite struct LiveStateTests {
    let now = Date(timeIntervalSince1970: 1_794_560_000)

    @Test func newerObservationWinsAndOldOnesFade() async {
        let store = LiveStore()
        let ends = now.addingTimeInterval(3600)
        await store.record("a", TripLive(delay: 60, observedAt: now, isCancelled: false, endsAt: ends))
        await store.record("a", TripLive(delay: 999, observedAt: now.addingTimeInterval(-10), isCancelled: false, endsAt: ends))
        #expect(await store.fresh(at: now)["a"]?.delay == 60)
        await store.record("a", TripLive(delay: 120, observedAt: now.addingTimeInterval(5), isCancelled: false, endsAt: ends))
        #expect(await store.fresh(at: now.addingTimeInterval(5))["a"]?.delay == 120)
        #expect(await store.fresh(at: now.addingTimeInterval(186))["a"] == nil, "older than 3 min is dropped")
    }

    @Test func endedTripsAreDeleted() async {
        let store = LiveStore()
        await store.record("a", TripLive(delay: 60, observedAt: now, isCancelled: false, endsAt: now))
        await store.prune(at: now.addingTimeInterval(600))
        #expect(await store.count == 1)
        await store.prune(at: now.addingTimeInterval(661))
        #expect(await store.count == 0)
    }

    /// The snapshot for every recorded departure stays well under 4 KB gzipped.
    @Test func snapshotOfAllFixturesIsSmall() async throws {
        let store = LiveStore()
        let recorder = Recorder(timetable: Fixtures.timetable, store: store)
        var latest = Date.distantPast
        for response in Fixtures.responses {
            await recorder.record(response.departures, at: response.at)
            latest = max(latest, response.at)
        }
        let cache = SnapshotCache(now: latest, upstream: .degraded)
        await cache.rebuild(from: store, upstream: .ok, at: latest)
        let body = await cache.current
        let snapshot = await cache.snapshot
        #expect(!snapshot.trips.isEmpty)
        #expect(body.gzipped.count < 4096, "\(body.gzipped.count) bytes")
        #expect(Gzip.decompress(body.gzipped) == body.json)
        let decoded = try JSONDecoder().decode(LiveSnapshot.self, from: body.json)
        #expect(decoded == snapshot)
        #expect(body.etag.count == 18)
    }

    @Test func offSnapshotHasNoTrips() async {
        let store = LiveStore()
        await store.record("a", TripLive(delay: 60, observedAt: now, isCancelled: false, endsAt: now.addingTimeInterval(99)))
        let cache = SnapshotCache(now: now, upstream: .degraded)
        await cache.rebuild(from: store, upstream: .off, at: now)
        #expect(await cache.snapshot.trips.isEmpty)
        #expect(await cache.snapshot.upstream == .off)
    }
}

@Suite struct PollingTests {
    static func poller(clock: ManualClock, source: FakeSource, enabled: Bool = true) -> (PollScheduler, SnapshotCache) {
        let metrics = Metrics()
        let store = LiveStore()
        let guarded = GuardedSource(source: source, limiter: RateLimiter(clock: clock), breaker: CircuitBreaker(clock: clock),
                                    metrics: metrics, isEnabled: enabled)
        let snapshot = SnapshotCache(now: clock.now(), upstream: .degraded)
        let hubs = Fixtures.timetable.hubs().stations
        let poller = PollScheduler(timetable: Fixtures.timetable, hubs: hubs, source: guarded, store: store,
                                   snapshot: snapshot, metrics: metrics, clock: clock, isEnabled: enabled, gap: { 0.2 })
        return (poller, snapshot)
    }

    @Test func aCycleAsksEachHubOnceAndPublishes() async throws {
        let sternenplatz = try #require(Fixtures.responses.first { $0.name.hasPrefix("dm_sternenplatz_20261113") })
        let clock = ManualClock(sternenplatz.at)
        let source = FakeSource { _ in sternenplatz.departures }
        let (poller, snapshot) = Self.poller(clock: clock, source: source)
        let state = await poller.cycle()
        #expect(state == .ok)
        #expect(source.callCount == Fixtures.timetable.hubs().stations.count)
        #expect(await !snapshot.snapshot.trips.isEmpty)
        // One request at a time, never faster than the cap.
        #expect(clock.now().timeIntervalSince(sternenplatz.at) >= Double(source.callCount - 2))
    }

    @Test func quietHoursSendNothing() async {
        // 03:00 on a Tuesday: no city bus runs in the next 20 minutes.
        let clock = ManualClock(BerlinTime.date(serviceDay: 20_261_117, minute: 180))
        let source = FakeSource()
        let (poller, _) = Self.poller(clock: clock, source: source)
        _ = await poller.cycle()
        #expect(source.callCount == 0)
    }

    @Test func killSwitchPublishesOff() async {
        let clock = ManualClock(BerlinTime.date(serviceDay: 20_261_117, minute: 600))
        let source = FakeSource()
        let (poller, snapshot) = Self.poller(clock: clock, source: source, enabled: false)
        #expect(await poller.cycle() == .off)
        #expect(source.callCount == 0)
        #expect(await snapshot.snapshot.upstream == .off)
    }

    @Test func failingSourceIsDegradedNotAnError() async {
        let clock = ManualClock(BerlinTime.date(serviceDay: 20_261_117, minute: 600))
        let source = FakeSource { _ in throw UpstreamError.status(500, retryAfter: nil) }
        let (poller, snapshot) = Self.poller(clock: clock, source: source)
        #expect(await poller.cycle() == .degraded)
        // The breaker backs off after the first failure instead of hammering the source.
        #expect(source.callCount == 1)
        #expect(await snapshot.snapshot.upstream == .degraded)
    }
}

@Suite struct StopDeparturesTests {
    @Test func thousandRequestsMakeOneUpstreamCall() async throws {
        let sternenplatz = try #require(Fixtures.responses.first { $0.name.hasPrefix("dm_sternenplatz_20261113") })
        let source = FakeSource { _ in
            try await Task.sleep(for: .milliseconds(100))
            return sternenplatz.departures
        }
        let guarded = GuardedSource(source: source, limiter: RateLimiter(), breaker: CircuitBreaker(), metrics: Metrics())
        let stops = StopDepartures(timetable: Fixtures.timetable, source: guarded, store: LiveStore())
        let answers = await withTaskGroup(of: StopDeparturesDTO?.self) { group in
            for _ in 0..<1000 { group.addTask { await stops.departures(gid: "de:08335:11918", limit: 10) } }
            return await group.reduce(into: [StopDeparturesDTO?]()) { $0.append($1) }
        }
        #expect(source.callCount == 1)
        #expect(answers.allSatisfy { $0 != nil })
    }

    @Test func unknownStopIsNil() async {
        let guarded = GuardedSource(source: FakeSource(), limiter: RateLimiter(), breaker: CircuitBreaker(), metrics: Metrics())
        let stops = StopDepartures(timetable: Fixtures.timetable, source: guarded, store: LiveStore())
        #expect(await stops.departures(gid: "de:99999:1", limit: 10) == nil)
        #expect(await stops.departures(gid: "de:08335:11918&x=1", limit: 10) == nil)
    }

    @Test func failingSourceFallsBackToTheTimetable() async throws {
        let clock = ManualClock(BerlinTime.date(serviceDay: 20_261_117, minute: 600))
        let guarded = GuardedSource(source: FakeSource { _ in throw UpstreamError.timeout },
                                    limiter: RateLimiter(clock: clock), breaker: CircuitBreaker(clock: clock), metrics: Metrics())
        let stops = StopDepartures(timetable: Fixtures.timetable, source: guarded, store: LiveStore(), clock: clock)
        let answer = try #require(await stops.departures(gid: "de:08335:11918", limit: 5))
        #expect(answer.upstream == .degraded)
        #expect(answer.departures.count == 5)
        #expect(answer.departures.allSatisfy { $0.realtime == nil && $0.k != nil })
    }
}

@Suite struct ConfigTests {
    @Test func defaultsAndCaps() {
        let config = LiveConfig(environment: ["UPSTREAM_MAX_RPS": "50", "POLL_INTERVAL_SECONDS": "1",
                                              "LIVE_UPSTREAM_ENABLED": "FALSE", "CONTACT_EMAIL": "ops@example.org"])
        #expect(config.upstreamMaxRPS == 1, "never above 1 request per second")
        #expect(config.pollIntervalSeconds == 10)
        #expect(!config.upstreamEnabled)
        #expect(config.userAgent.contains("ops@example.org"))
        #expect(LiveConfig(environment: [:]).port == 8080)
    }
}
