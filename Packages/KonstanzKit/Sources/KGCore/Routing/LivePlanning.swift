import Foundation

extension JourneyPlanner {
    /// How many times a plan is redone without a bus it can't catch.
    private static let liveRounds = 3

    /// Plans with what's known right now: cancelled buses are left out, and a change that a delay has already
    /// broken isn't offered. Without any reports this is the plain timetable plan, so offline nothing changes.
    public func plan(_ request: PlanRequest, live: LiveState) throws -> [Journey] {
        var avoiding = live.cancelled
        var journeys = try plan(request, avoiding: avoiding)
        guard !live.delays.isEmpty || !live.cancelled.isEmpty else { return journeys }
        for _ in 0..<Self.liveRounds {
            let unreachable = Set(journeys.compactMap { journey -> Int? in
                switch journey.risk(at: request.time, live: live) {
                case let .missed(next, _): next.tripID
                case let .cancelled(ride): ride.tripID
                default: nil
                }
            })
            if unreachable.isEmpty { break }
            avoiding.formUnion(unreachable)
            journeys = try plan(request, avoiding: avoiding)
        }
        let working = journeys.filter { !$0.risk(at: request.time, live: live).isBroken }
        guard request.preference == .fastest, !request.arriveBy else { return working }
        // When they really arrive decides what's fastest.
        return working.enumerated().sorted { lhs, rhs in
            (live.expectedEnd(lhs.element), lhs.offset) < (live.expectedEnd(rhs.element), rhs.offset)
        }.map(\.element)
    }

    /// Leaves out bus options that lose on every count to another: leaving earlier, arriving later, more walking
    /// and more changes. Walking stays: it needs no waiting and no bus.
    static func withoutDominated(_ journeys: [Journey]) -> [Journey] {
        journeys.filter { journey in
            journey.rides.isEmpty || !journeys.contains { other in
                other.id != journey.id && other.start >= journey.start && other.end <= journey.end
                    && other.walkingMinutes <= journey.walkingMinutes && other.transfers <= journey.transfers
                    && (other.start > journey.start || other.end < journey.end
                        || other.walkingMinutes < journey.walkingMinutes || other.transfers < journey.transfers)
            }
        }
    }
}

/// A moment to tell the rider their stop is coming.
public struct GetOffMoment: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case twoStopsLeft
        case nextStop
    }

    public var kind: Kind
    public var date: Date
    public var stop: String
    public var line: String
}

extension Journey {
    /// When to remind the rider, by the timetable and the delays known now. Earlier stops of a short ride are
    /// skipped when they'd say nothing new.
    public func getOffMoments(live: LiveState, now: Date) -> [GetOffMoment] {
        rides.flatMap { ride -> [GetOffMoment] in
            let shift = live.delays[ride.tripID] ?? 0
            let count = ride.stops.count
            var moments = [GetOffMoment(kind: .nextStop, date: ride.stops[count - 2].departure.addingTimeInterval(shift),
                                        stop: ride.alighting.station.shortName, line: ride.line.name)]
            if count >= 4 {
                moments.insert(GetOffMoment(kind: .twoStopsLeft, date: ride.stops[count - 3].departure.addingTimeInterval(shift),
                                            stop: ride.alighting.station.shortName, line: ride.line.name), at: 0)
            }
            return moments.filter { $0.date > now }
        }
    }
}
