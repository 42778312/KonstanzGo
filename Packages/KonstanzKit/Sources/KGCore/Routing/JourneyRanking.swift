import Foundation

// Ordering and labelling of journey options, and fitting a trip's shape to the part ridden.
extension JourneyPlanner {
    /// Sorts journeys by a preference; ties go to the earlier arrival.
    public static func ranked(_ journeys: [Journey], by preference: RoutePreference, arriveBy: Bool) -> [Journey] {
        journeys.sorted { lhs, rhs in
            switch preference {
            case .fastest:
                if arriveBy, lhs.start != rhs.start { return lhs.start > rhs.start }
                return (lhs.end, lhs.minutes) < (rhs.end, rhs.minutes)
            case .leastWalking:
                return (lhs.walkingMinutes, lhs.end) < (rhs.walkingMinutes, rhs.end)
            case .fewestTransfers:
                return (lhs.transfers, lhs.end) < (rhs.transfers, rhs.end)
            }
        }
    }

    /// The labels on the cards (screen 10): the earliest arrival is "Schnellste"; the journey with
    /// clearly less walking or fewer changes gets that label when it is a different one.
    public static func tags(for journeys: [Journey]) -> [String: Set<JourneyTag>] {
        guard !journeys.isEmpty else { return [:] }
        var tags: [String: Set<JourneyTag>] = [:]
        let fastest = journeys.min { ($0.end, $0.minutes) < ($1.end, $1.minutes) }
        if let fastest { tags[fastest.id, default: []].insert(.fastest) }
        let bus = journeys.filter { !$0.rides.isEmpty }
        if let least = bus.min(by: { ($0.walkingMinutes, $0.end) < ($1.walkingMinutes, $1.end) }),
           let fastest, least.id != fastest.id, least.walkingMinutes < fastest.walkingMinutes {
            tags[least.id, default: []].insert(.leastWalking)
        }
        if let fewest = bus.min(by: { ($0.transfers, $0.end) < ($1.transfers, $1.end) }),
           let fastest, fewest.id != fastest.id, fewest.transfers < fastest.transfers {
            tags[fewest.id, default: []].insert(.fewestTransfers)
        }
        return tags
    }

    /// The part of a trip's shape along the platforms ridden, matched stop by stop (ring lines drive a street
    /// twice, and lines like 9 loop out to a turning point and back). The piece is checked against the way
    /// from stop to stop, not the straight line from first to last, which a loop is much longer than. Falls back
    /// to the stops joined up when the shape does not fit.
    static func slice(_ shape: [Coordinate], along stops: [Coordinate]) -> [Coordinate] {
        guard let from = stops.first, let to = stops.last, stops.count >= 2 else { return stops }
        let dense = Shapes.densify(shape)
        let viaStops = zip(stops, stops.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard let matched = Shapes.match(stops, to: dense), let start = matched.first, let end = matched.last,
              end > start
        else { return stops }
        let piece = Array(dense[start...end])
        let length = zip(piece, piece.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard length <= 1.8 * viaStops + 200 else { return stops }
        return [from] + piece + [to]
    }
}
