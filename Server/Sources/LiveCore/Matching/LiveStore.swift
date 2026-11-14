import Foundation
import KGLiveAPI

/// What the server knows about one running trip right now.
public struct TripLive: Sendable, Hashable {
    /// Seconds behind the timetable; negative when early.
    public var delay: Int
    public var observedAt: Date
    public var isCancelled: Bool
    /// When the trip ends by the timetable; it is forgotten 10 min after that (plus its delay).
    public var endsAt: Date
}

/// The live state: trip key → latest observation. The poller writes, the snapshot builder reads. A newer
/// observation always replaces an older one; delays are not averaged.
public actor LiveStore {
    public static let maxAge: TimeInterval = 180
    static let keepAfterEnd: TimeInterval = 600

    private var trips: [String: TripLive] = [:]

    public init() {}

    public func record(_ key: String, _ live: TripLive) {
        if let known = trips[key], known.observedAt > live.observedAt { return }
        trips[key] = live
    }

    /// Fresh entries only: anything older than 3 min is not shown, so the app falls back to the timetable.
    public func fresh(at now: Date) -> [String: TripLive] {
        trips.filter { now.timeIntervalSince($0.value.observedAt) <= Self.maxAge }
    }

    /// Deletes trips that ended more than 10 min ago.
    public func prune(at now: Date) {
        trips = trips.filter {
            now.timeIntervalSince($0.value.endsAt.addingTimeInterval(TimeInterval(max($0.value.delay, 0)))) <= Self.keepAfterEnd
        }
    }

    public var count: Int { trips.count }
}
