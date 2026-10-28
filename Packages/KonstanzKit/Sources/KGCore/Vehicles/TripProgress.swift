import Foundation

/// How far along a ride is (screen 11 "Unterwegs", the Live Activity): "Noch 4 Haltestellen", "11 Min.",
/// "Ankunft 14:35", the progress bar and which stop is "jetzt".
public struct TripProgress: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        /// Before the bus leaves the boarding stop.
        case waiting
        /// Standing at a stop on the way (`currentStop`).
        case atStop
        /// Between `currentStop` and the next one.
        case driving
        /// At or past the stop where you get off.
        case arrived
    }

    public var phase: Phase
    /// Index into the ride's stops: the stop the bus is at, or the last one it passed.
    public var currentStop: Int
    /// Stops still to come up to and including the one where you get off ("Noch 4 Haltestellen").
    public var stopsLeft: Int
    /// Whole minutes until arrival, rounded up; 0 when arrived.
    public var minutesToArrival: Int
    /// 0 at boarding, 1 at arrival, by time.
    public var fraction: Double
    public var arrival: Date

    /// Progress of `ride` at `now`, by the timetable.
    public init(ride: RideLeg, at now: Date) {
        let stops = ride.stops
        arrival = ride.end
        let total = ride.end.timeIntervalSince(ride.start)
        fraction = total > 0 ? min(1, max(0, now.timeIntervalSince(ride.start) / total)) : (now >= ride.end ? 1 : 0)
        minutesToArrival = max(0, Int((ride.end.timeIntervalSince(now) / 60).rounded(.up)))

        if now < ride.start {
            phase = .waiting
            currentStop = 0
            stopsLeft = stops.count - 1
        } else if now >= ride.end {
            phase = .arrived
            currentStop = stops.count - 1
            stopsLeft = 0
        } else {
            // The last stop the bus has reached by now.
            let reached = stops.lastIndex { $0.arrival <= now } ?? 0
            currentStop = reached
            phase = now <= stops[reached].departure ? .atStop : .driving
            stopsLeft = stops.count - 1 - reached
        }
    }

    /// Progress from the user's position instead of the clock, for when the bus runs late: the stop nearest to
    /// the user along the ride (within 150 m) counts as reached. Falls back to the timetable when off the route.
    public init(ride: RideLeg, at now: Date, near position: Coordinate) {
        self.init(ride: ride, at: now)
        guard phase != .arrived else { return }
        let distances = ride.stops.map { $0.platform.coordinate.distance(to: position) }
        guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[nearest] <= 150
        else { return }
        currentStop = nearest
        stopsLeft = ride.stops.count - 1 - nearest
        phase = nearest == ride.stops.count - 1 ? .arrived : (distances[nearest] <= 40 ? .atStop : .driving)
        if phase == .arrived { minutesToArrival = 0 }
    }
}
