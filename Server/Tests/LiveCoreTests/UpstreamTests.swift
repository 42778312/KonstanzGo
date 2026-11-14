import Foundation
@testable import LiveCore
import Testing

@Suite struct ParserTests {
    @Test func everyFixtureParses() throws {
        #expect(Fixtures.responses.count >= 6)
        for response in Fixtures.responses {
            #expect(!response.gid.isEmpty, "\(response.name) names its stop")
            #expect(!response.departures.isEmpty, "\(response.name) has departures")
        }
    }

    @Test func readsTimesLinePlatformAndDelay() throws {
        let sternenplatz = try #require(Fixtures.responses.first { $0.name.hasPrefix("dm_sternenplatz_20261113") })
        let first = try #require(sternenplatz.departures.first)
        #expect(first.line == "12")
        #expect(first.platform == "de:08335:11918:0:2")
        #expect(first.destinationName == "Wollmatingen Radolfzeller Str.")
        #expect(first.planned == (try Date("2026-11-13T10:13:00Z", strategy: .iso8601)))
        #expect(first.delay == 186)
        #expect(first.isCityBus)
        #expect(!first.isCancelled)
    }

    @Test func unmonitoredBusesHaveNoDelay() {
        let all = Fixtures.responses.flatMap(\.departures)
        #expect(all.contains { $0.realtime == nil })
        #expect(all.filter { $0.realtime == nil }.allSatisfy { $0.delay == nil })
    }

    @Test func cancelledAndEmptyResponses() throws {
        let json = Data("""
        {"stopEvents":[{"realtimeStatus":["TRIP_CANCELLED"],"location":{"id":"de:08335:11918:0:1"},
        "departureTimePlanned":"2026-11-13T10:13:00Z","transportation":{"number":"9 A","product":{"class":5},
        "destination":{"name":"Uni"}}}]}
        """.utf8)
        let parsed = try EFAParser.parse(json, stopGID: "de:08335:11918")
        #expect(parsed.first?.isCancelled == true)
        #expect(parsed.first?.line == "9A")
        #expect(try EFAParser.parse(Data("{}".utf8), stopGID: "x").isEmpty)
        #expect(throws: UpstreamError.self) { try EFAParser.parse(Data("<html>".utf8), stopGID: "x") }
    }

    @Test func urlAsksForRapidJSONByGID() {
        let url = EFAParser.url(stopGID: "de:08335:11918", limit: 40)
        #expect(url.contains("outputFormat=rapidJSON"))
        #expect(url.contains("name_dm=de:08335:11918"))
        #expect(url.contains("useRealtime=1"))
    }
}

@Suite struct GuardTests {
    /// Grant times, then the largest number in any 60 s window.
    static func busiestMinute(_ times: [Date]) -> Int {
        var best = 0, start = 0
        for end in times.indices {
            while times[end].timeIntervalSince(times[start]) >= 60 { start += 1 }
            best = max(best, end - start + 1)
        }
        return best
    }

    @Test func tenThousandRequestsNeverExceedSixtyAMinute() async throws {
        let clock = ManualClock()
        let source = FakeSource()
        let guarded = GuardedSource(source: source, limiter: RateLimiter(rate: 1, burst: 2, maxWait: 1_000_000, clock: clock),
                                    breaker: CircuitBreaker(clock: clock), metrics: Metrics())
        var times: [Date] = []
        for index in 0..<10_000 {
            // Callers arrive in bursts and lulls; the limiter evens them out.
            if index % 50 == 0 { clock.advance(Double(index % 7)) }
            _ = try await guarded.departures(stopGID: "de:08335:11918", limit: 40)
            times.append(clock.now())
        }
        #expect(source.callCount == 10_000)
        #expect(Self.busiestMinute(times) <= 60)
    }

    @Test func burstOfTwoThenOnePerSecond() async {
        let clock = ManualClock()
        let limiter = RateLimiter(rate: 1, burst: 2, clock: clock)
        let start = clock.now()
        var offsets: [Double] = []
        for _ in 0..<5 {
            _ = await limiter.acquire()
            offsets.append(clock.now().timeIntervalSince(start))
        }
        #expect(offsets.map { $0.rounded() } == [0, 0, 1, 2, 3])
    }

    @Test func deniesWhenTheQueueIsTooLong() async {
        let limiter = RateLimiter(rate: 1, burst: 2, maxWait: 10, clock: ManualClock())
        var outcomes: [RateLimiter.Outcome] = []
        // Reserve without the clock moving: the 13th caller would wait 11 s.
        for _ in 0..<13 {
            outcomes.append(await limiter.reserveForTest())
        }
        #expect(outcomes.prefix(12).allSatisfy { $0 == .granted })
        #expect(outcomes.last == .denied)
    }

    @Test func breakerOpensHalfOpensAndCloses() async {
        let clock = ManualClock()
        let breaker = CircuitBreaker(clock: clock, jitter: { 1 })
        for _ in 0..<5 {
            clock.advance(400)
            #expect(await breaker.allow())
            await breaker.recordFailure()
        }
        #expect(await breaker.state == .open)
        clock.advance(119)
        #expect(await !breaker.allow())
        clock.advance(2)
        #expect(await breaker.allow())
        #expect(await breaker.state == .halfOpen)
        #expect(await !breaker.allow(), "only one probe at a time")
        await breaker.recordFailure()
        #expect(await breaker.state == .open)
        clock.advance(121)
        #expect(await breaker.allow())
        await breaker.recordSuccess()
        #expect(await breaker.state == .closed)
        #expect(await breaker.allow())
    }

    @Test func backoffDoublesAndHonoursRetryAfter() async {
        let clock = ManualClock()
        let breaker = CircuitBreaker(clock: clock, jitter: { 1 })
        await breaker.recordFailure()
        clock.advance(29)
        #expect(await !breaker.allow())
        clock.advance(2)
        #expect(await breaker.allow())
        await breaker.recordFailure()
        clock.advance(59)
        #expect(await !breaker.allow())
        clock.advance(2)
        #expect(await breaker.allow())
        await breaker.recordFailure(retryAfter: 600)
        clock.advance(300)
        #expect(await !breaker.allow())
        clock.advance(301)
        #expect(await breaker.allow())
    }

    @Test func a429CountsAsFailureButA404DoesNot() async throws {
        let clock = ManualClock()
        let breaker = CircuitBreaker(clock: clock, jitter: { 1 })
        let metrics = Metrics()
        let tooMany = GuardedSource(source: FakeSource { _ in throw UpstreamError.status(429, retryAfter: nil) },
                                    limiter: RateLimiter(clock: clock), breaker: breaker, metrics: metrics)
        await #expect(throws: UpstreamError.self) { try await tooMany.departures(stopGID: "a", limit: 1) }
        #expect(await !breaker.allow())
        #expect(await metrics.counter("upstream_requests_total", label: "429") == 1)
        let other = CircuitBreaker(clock: clock)
        let missing = GuardedSource(source: FakeSource { _ in throw UpstreamError.status(404, retryAfter: nil) },
                                    limiter: RateLimiter(clock: clock), breaker: other, metrics: metrics)
        await #expect(throws: UpstreamError.self) { try await missing.departures(stopGID: "a", limit: 1) }
        #expect(await other.allow())
    }

    @Test func killSwitchSendsNothing() async {
        let source = FakeSource()
        let guarded = GuardedSource(source: source, limiter: RateLimiter(clock: ManualClock()),
                                    breaker: CircuitBreaker(), metrics: Metrics(), isEnabled: false)
        await #expect(throws: UpstreamError.disabled) { try await guarded.departures(stopGID: "a", limit: 1) }
        #expect(source.callCount == 0)
    }
}
