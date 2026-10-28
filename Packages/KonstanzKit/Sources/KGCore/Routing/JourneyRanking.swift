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

    /// The part of a trip's shape between two platforms (nearest shape points to each).
    static func slice(_ shape: [Coordinate], from: Coordinate, to: Coordinate) -> [Coordinate] {
        guard shape.count >= 2 else { return [from, to] }
        func nearest(_ point: Coordinate, after start: Int) -> Int {
            var best = start, bestDistance = Double.infinity
            for index in start..<shape.count {
                let distance = shape[index].distance(to: point)
                if distance < bestDistance { bestDistance = distance; best = index }
            }
            return best
        }
        let first = nearest(from, after: 0)
        let last = nearest(to, after: first)
        return [from] + shape[first...last] + [to]
    }
}
