import Foundation

/// Time, injectable so tests can run a day of traffic in milliseconds.
public protocol LiveClock: Sendable {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

public struct SystemClock: LiveClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .milliseconds(Int64((seconds * 1000).rounded(.up))))
    }
}

/// The hard upstream cap: a token bucket (`rate` per second, `burst` at once) plus a sliding window that never
/// lets more than `rate × 60` requests through in any minute. Callers wait their turn, or are denied when the
/// wait would be longer than `maxWait`.
public actor RateLimiter {
    public enum Outcome: Sendable, Equatable { case granted, denied }

    let rate: Double
    let burst: Double
    let maxWait: Double
    let perMinute: Int
    let clock: any LiveClock
    private var tokens: Double
    private var updated: Date
    /// Grant times of the last minute, oldest first.
    private var grants: [Date] = []

    public init(rate: Double = 1, burst: Int = 2, maxWait: Double = 10, clock: any LiveClock = SystemClock()) {
        self.rate = max(rate, 0.01)
        self.burst = Double(max(burst, 1))
        self.maxWait = maxWait
        perMinute = max(Int((self.rate * 60).rounded(.down)), 1)
        self.clock = clock
        tokens = self.burst
        updated = clock.now()
    }

    /// Reserves the next slot and waits for it.
    public func acquire() async -> Outcome {
        guard let wait = reserve() else { return .denied }
        if wait > 0 { try? await clock.sleep(seconds: wait) }
        return .granted
    }

    /// Reserves without waiting, for tests that check the queue.
    func reserveForTest() -> Outcome { reserve() == nil ? .denied : .granted }

    /// Books the next free slot and returns how long until it, or nil when that is longer than `maxWait`.
    private func reserve() -> Double? {
        let now = clock.now()
        tokens = min(burst, tokens + now.timeIntervalSince(updated) * rate)
        updated = now
        // The earliest moment the bucket has a token for us ...
        var at = now.addingTimeInterval(tokens >= 1 ? 0 : (1 - tokens) / rate)
        // ... and the last minute has room: the grant `perMinute` back must be a full minute earlier.
        grants.removeAll { $0 <= now.addingTimeInterval(-60) }
        if grants.count >= perMinute {
            at = max(at, grants[grants.count - perMinute].addingTimeInterval(60))
        }
        let wait = at.timeIntervalSince(now)
        guard wait <= maxWait else { return nil }
        tokens -= 1
        grants.append(at)
        return wait
    }
}

/// Stops asking a source that keeps failing. Closed: requests pass. After a failure, waits 30 s, 60 s, 120 s ...
/// (at most 5 min, with jitter, or the source's `Retry-After`). After 5 failures in a row it opens for 2 min, then
/// lets one probe through; success closes it.
public actor CircuitBreaker {
    public enum State: String, Sendable { case closed, open, halfOpen = "half_open" }

    let threshold: Int
    let openSeconds: Double
    let clock: any LiveClock
    let jitter: @Sendable () -> Double
    public private(set) var state: State = .closed
    private var failures = 0
    private var blockedUntil: Date?
    private var probeInFlight = false

    public init(threshold: Int = 5, openSeconds: Double = 120, clock: any LiveClock = SystemClock(),
                jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.8...1.2) }) {
        self.threshold = threshold
        self.openSeconds = openSeconds
        self.clock = clock
        self.jitter = jitter
    }

    /// Whether a request may go out now. In half-open, only one probe at a time.
    public func allow() -> Bool {
        let now = clock.now()
        if let blockedUntil, now < blockedUntil { return false }
        switch state {
        case .closed: return true
        case .open, .halfOpen:
            guard !probeInFlight else { return false }
            state = .halfOpen
            probeInFlight = true
            return true
        }
    }

    public func recordSuccess() {
        failures = 0
        blockedUntil = nil
        probeInFlight = false
        state = .closed
    }

    /// `retryAfter` in seconds, when the source said so.
    public func recordFailure(retryAfter: Int? = nil) {
        failures += 1
        probeInFlight = false
        let now = clock.now()
        var wait: Double
        if failures >= threshold || state == .halfOpen {
            state = .open
            wait = openSeconds
        } else {
            wait = min(30 * pow(2, Double(failures - 1)), 300) * jitter()
        }
        if let retryAfter { wait = max(wait, Double(min(retryAfter, 3600))) }
        blockedUntil = now.addingTimeInterval(wait)
    }

    /// Nothing went out (rate limit), so nothing is learned; frees a half-open probe slot.
    public func recordSkipped() { probeInFlight = false }
}

/// The only `RealtimeSource` the server uses: every call goes through the shared rate limiter and the breaker,
/// and is counted.
public struct GuardedSource: RealtimeSource {
    let source: any RealtimeSource
    let limiter: RateLimiter
    let breaker: CircuitBreaker
    let metrics: Metrics
    let isEnabled: Bool

    public init(source: any RealtimeSource, limiter: RateLimiter, breaker: CircuitBreaker, metrics: Metrics,
                isEnabled: Bool = true) {
        self.source = source
        self.limiter = limiter
        self.breaker = breaker
        self.metrics = metrics
        self.isEnabled = isEnabled
    }

    public func departures(stopGID: String, limit: Int) async throws -> [UpstreamDeparture] {
        guard isEnabled else { throw UpstreamError.disabled }
        guard await breaker.allow() else {
            await metrics.count("upstream_skipped_total", label: "circuit_open")
            throw UpstreamError.circuitOpen
        }
        guard await limiter.acquire() == .granted else {
            await breaker.recordSkipped()
            await metrics.count("upstream_skipped_total", label: "denied")
            throw UpstreamError.denied
        }
        do {
            let result = try await source.departures(stopGID: stopGID, limit: limit)
            await breaker.recordSuccess()
            await metrics.count("upstream_requests_total", label: "200")
            return result
        } catch let error as UpstreamError {
            await metrics.count("upstream_requests_total", label: error.metricLabel)
            if case let .status(code, retry) = error, code < 500, code != 429 {
                // A 4xx other than 429 is our mistake, not an overloaded source: don't back off everything.
                await breaker.recordSuccess()
                _ = retry
            } else if case let .status(_, retry) = error {
                await breaker.recordFailure(retryAfter: retry)
            } else {
                await breaker.recordFailure()
            }
            throw error
        } catch {
            await metrics.count("upstream_requests_total", label: "transport")
            await breaker.recordFailure()
            throw UpstreamError.transport(String(describing: error))
        }
    }

    public func circuitState() async -> CircuitBreaker.State { await breaker.state }
}
