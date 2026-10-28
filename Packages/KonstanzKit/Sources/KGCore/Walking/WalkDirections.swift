import Foundation

/// Turns a walking route into steps: a new step wherever the way (its name, or its kind when unnamed)
/// changes. Short connectors and the first and last few metres are folded into their neighbours.
/// Same rules as the Android app.
struct WalkDirections {
    let graph: WalkGraph
    let pieces: [WalkRouter.Piece]

    private struct Group {
        var name: String?
        var kind: WayKind
        var onBridge: Bool
        var points: [Coordinate]

        var metres: Double { zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }

        func sameWay(as other: Group) -> Bool {
            name != nil || other.name != nil ? name == other.name : kind == other.kind
        }

        /// Whether `next` continues this group (crossings in a row also merge).
        func absorbs(_ next: Group) -> Bool {
            (sameWay(as: next) && next.kind != .crossing) || (kind == .crossing && next.kind == .crossing)
        }
    }

    func steps() -> [WalkStep] {
        guard !pieces.isEmpty else { return [] }
        var groups = merged(pieces.map {
            Group(name: graph.name(of: $0.edge), kind: graph.edgeKind[$0.edge], onBridge: graph.isBridge($0.edge),
                  points: $0.points)
        })
        groups = merged(withoutShortConnectors(groups))
        groups = trimmedEnds(groups)

        var steps: [WalkStep] = []
        for (index, group) in groups.enumerated() {
            let maneuver: Maneuver
            if index == 0 {
                maneuver = .depart
            } else if group.kind == .steps {
                maneuver = .stairs
            } else if group.kind == .crossing {
                maneuver = .cross
            } else {
                maneuver = Self.maneuver(forTurn: Self.turnAngle(before: groups[index - 1].points, after: group.points))
            }
            steps.append(WalkStep(maneuver: maneuver, street: group.name, way: group.kind, onBridge: group.onBridge,
                                  metres: Self.rounded(metres: group.metres), start: group.points[0],
                                  heading: Self.bearing(from: group.points)))
        }
        if let end = groups.last?.points.last {
            steps.append(WalkStep(maneuver: .arrive, street: nil, metres: 0, start: end))
        }
        return steps
    }

    private func merged(_ groups: [Group]) -> [Group] {
        var result: [Group] = []
        for group in groups {
            if let last = result.last, last.absorbs(group) {
                result[result.count - 1].points += group.points.dropFirst()
            } else {
                result.append(group)
            }
        }
        return result
    }

    /// Short unnamed connectors (a few metres of path between two streets) are not worth a step.
    private func withoutShortConnectors(_ groups: [Group]) -> [Group] {
        var groups = groups
        var result: [Group] = []
        for index in groups.indices {
            let group = groups[index]
            let keep = index == 0 || index == groups.count - 1 || group.name != nil
                || group.kind == .crossing || group.kind == .steps || group.metres >= 15
            if keep {
                result.append(group)
            } else {
                groups[index + 1].points.insert(contentsOf: group.points.dropLast(), at: 0)
            }
        }
        return result
    }

    /// A few metres at either end (stepping onto the street) are not steps of their own.
    private func trimmedEnds(_ groups: [Group]) -> [Group] {
        var groups = groups
        var lead = 0.0
        while groups.count > 1, lead + groups[0].metres < 25 {
            lead += groups[0].metres
            let first = groups.removeFirst()
            groups[0].points.insert(contentsOf: first.points.dropLast(), at: 0)
        }
        while groups.count > 1, let last = groups.last, last.metres < 10, last.kind != .crossing {
            groups.removeLast()
            groups[groups.count - 1].points += last.points.dropFirst()
        }
        return groups
    }

    // MARK: Geometry

    /// Direction of the first ~20 m.
    static func bearing(from points: [Coordinate]) -> Double {
        var walked = 0.0
        for index in 1..<max(points.count, 1) {
            walked += points[index - 1].distance(to: points[index])
            if walked >= 20 || index == points.count - 1 { return points[0].bearing(to: points[index]) }
        }
        return 0
    }

    /// Direction of the last ~20 m.
    static func bearing(into points: [Coordinate]) -> Double {
        guard let last = points.last, points.count > 1 else { return 0 }
        var walked = 0.0
        for index in stride(from: points.count - 2, through: 0, by: -1) {
            walked += points[index].distance(to: points[index + 1])
            if walked >= 20 || index == 0 { return points[index].bearing(to: last) }
        }
        return 0
    }

    /// Signed turn in degrees: + right, − left.
    static func turnAngle(before: [Coordinate], after: [Coordinate]) -> Double {
        (bearing(from: after) - bearing(into: before) + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    static func maneuver(forTurn turn: Double) -> Maneuver {
        switch turn {
        case -25..<25: .straight
        case 25..<60: .slightRight
        case 60..<135: .right
        case 135..<165: .sharpRight
        case -60 ..< -25: .slightLeft
        case -135 ..< -60: .left
        case -165 ..< -135: .sharpLeft
        default: .uTurn
        }
    }

    /// 5 m steps under 100 m (at least 5), then 10 m steps.
    static func rounded(metres: Double) -> Int {
        metres < 100 ? max(5, Int((metres / 5).rounded()) * 5) : Int((metres / 10).rounded()) * 10
    }
}
