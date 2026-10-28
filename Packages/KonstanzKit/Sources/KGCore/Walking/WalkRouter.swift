import Foundation

/// A walk along the streets: its shape, length and turn-by-turn steps.
public struct WalkRoute: Sendable, Hashable {
    public var path: [Coordinate]
    public var metres: Double
    public var steps: [WalkStep]

    public var minutes: Int { Walking.minutes(forMetres: metres) }
}

/// Walking directions over the offline network: A* from the nearest street to the start to the nearest
/// street to the target, then the route is cut into steps where the street changes.
/// Same approach as the Android app's `WalkRouter`.
public struct WalkRouter: Sendable {
    public let graph: WalkGraph

    public init(graph: WalkGraph) {
        self.graph = graph
    }

    /// nil when a point is not near the network (outside the map) or there is no way through.
    public func route(from start: Coordinate, to target: Coordinate) -> WalkRoute? {
        let sources = candidates(near: start), targets = candidates(near: target)
        guard !sources.isEmpty, !targets.isEmpty, let pieces = search(from: sources, to: targets) else { return nil }

        var path = [start]
        for (_, points) in pieces {
            for point in points where point != path.last { path.append(point) }
        }
        if path.last != target { path.append(target) }
        let metres = zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        let steps = WalkDirections(graph: graph, pieces: pieces.filter { $0.points.count > 1 }).steps()
        return WalkRoute(path: path, metres: metres, steps: steps)
    }

    // MARK: Snapping

    /// The nearest point on the network to a coordinate.
    struct Snap {
        var edge: Int
        var point: Coordinate
        /// Metres along the edge from vertex A.
        var alongFromA: Double
        var distance: Double
    }

    /// Nearest point on the network within about 400 m. Stairs only when nothing else is near.
    func snap(_ point: Coordinate) -> Snap? {
        let centre = WalkGraph.cell(point.latitude, point.longitude)
        var best: Snap?
        for ring in 0...4 {
            for y in (centre.y - ring)...(centre.y + ring) {
                for x in (centre.x - ring)...(centre.x + ring)
                where max(abs(y - centre.y), abs(x - centre.x)) == ring {
                    for edge in graph.cells[WalkGraph.key(y, x)] ?? [] {
                        if let candidate = nearest(on: edge, to: point),
                           candidate.distance < best?.distance ?? .infinity {
                            best = candidate
                        }
                    }
                }
            }
            // Anything found within the rings searched so far is the nearest (cells are ~110 × 75 m).
            if let best, best.distance < Double(ring) * 75 { break }
        }
        return best
    }

    /// The nearest way plus any other way almost as near (parallel sidewalks and roadways are often mapped
    /// side by side without a link), so the search can step across instead of walking around. At most four.
    func candidates(near point: Coordinate, slack: Double = 8) -> [Snap] {
        guard let nearest = snap(point) else { return [] }
        let centre = WalkGraph.cell(point.latitude, point.longitude)
        var byEdge: [Int: Snap] = [nearest.edge: nearest]
        for y in (centre.y - 1)...(centre.y + 1) {
            for x in (centre.x - 1)...(centre.x + 1) {
                for edge in graph.cells[WalkGraph.key(y, x)] ?? [] where byEdge[edge] == nil {
                    if let candidate = self.nearest(on: edge, to: point),
                       candidate.distance <= nearest.distance + slack {
                        byEdge[edge] = candidate
                    }
                }
            }
        }
        return Array(byEdge.values.sorted { $0.distance < $1.distance }.prefix(4))
    }

    private func nearest(on edge: Int, to point: Coordinate) -> Snap? {
        let shape = graph.points(edge)
        let penalty = graph.edgeKind[edge] == .steps ? 15.0 : 0
        var best: Snap?
        var along = 0.0
        for (from, to) in zip(shape, shape.dropFirst()) {
            let length = from.distance(to: to)
            let fraction = Self.project(point, from, to)
            let onSegment = from.interpolated(to: to, fraction: fraction)
            let distance = point.distance(to: onSegment) + penalty
            if distance < best?.distance ?? .infinity {
                best = Snap(edge: edge, point: onSegment, alongFromA: along + length * fraction, distance: distance)
            }
            along += length
        }
        return best
    }

    /// 0…1 position of the point nearest to `point` on the segment a–b.
    static func project(_ point: Coordinate, _ segmentStart: Coordinate, _ segmentEnd: Coordinate) -> Double {
        // Flat projection: longitude scaled by cos(latitude), fine over a few hundred metres.
        let scale = cos(point.latitude * .pi / 180)
        let segmentX = (segmentEnd.longitude - segmentStart.longitude) * scale
        let segmentY = segmentEnd.latitude - segmentStart.latitude
        let pointX = (point.longitude - segmentStart.longitude) * scale
        let pointY = point.latitude - segmentStart.latitude
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        guard lengthSquared > 0 else { return 0 }
        return min(1, max(0, (pointX * segmentX + pointY * segmentY) / lengthSquared))
    }

    // MARK: Search

    typealias Piece = (edge: Int, points: [Coordinate])

    private func cost(_ edge: Int) -> Double {
        graph.edgeLength[edge] * (graph.edgeKind[edge] == .steps ? 1.4 : 1.0)
    }

    // swiftlint:disable function_body_length cyclomatic_complexity
    /// A* from any start candidate to any target candidate; stepping onto a way costs its distance.
    /// The route comes back as pieces of edges in walking order.
    private func search(from sources: [Snap], to targets: [Snap]) -> [Piece]? {
        let count = graph.vertexCount
        var distance = [Double](repeating: .infinity, count: count)
        var viaEdge = [Int](repeating: -1, count: count)
        var viaVertex = [Int](repeating: -1, count: count)
        /// For a vertex reached straight from a start candidate: which one.
        var viaSource = [Int](repeating: -1, count: count)
        var done = [Bool](repeating: false, count: count)
        var queue = MinHeap()

        func estimate(_ vertex: Int) -> Double {
            let here = graph.vertex(vertex)
            return targets.map { here.distance(to: $0.point) }.min() ?? 0
        }
        func push(_ vertex: Int, _ cost: Double, edge: Int, from: Int, source: Int) {
            guard cost < distance[vertex] else { return }
            distance[vertex] = cost
            viaEdge[vertex] = edge
            viaVertex[vertex] = from
            viaSource[vertex] = source
            queue.push(cost + estimate(vertex), vertex)
        }
        func scale(_ snap: Snap) -> Double { cost(snap.edge) / max(graph.edgeLength[snap.edge], 0.01) }

        // Best so far: along one shared edge (source index, target index), or via a vertex.
        var best = Double.infinity
        var bestShared: (source: Int, target: Int)?
        var bestEnd: (vertex: Int, target: Int)?
        for (index, source) in sources.enumerated() {
            push(graph.edgeA[source.edge], source.distance + source.alongFromA * scale(source),
                 edge: -1, from: -1, source: index)
            push(graph.edgeB[source.edge],
                 source.distance + (graph.edgeLength[source.edge] - source.alongFromA) * scale(source),
                 edge: -1, from: -1, source: index)
            for (targetIndex, target) in targets.enumerated() where target.edge == source.edge {
                let shared = source.distance + abs(source.alongFromA - target.alongFromA) * scale(source)
                    + target.distance
                if shared < best { best = shared; bestShared = (index, targetIndex) }
            }
        }

        while let vertex = queue.pop() {
            if done[vertex] { continue }
            done[vertex] = true
            if distance[vertex] + estimate(vertex) >= best { break }
            for (index, target) in targets.enumerated()
            where vertex == graph.edgeA[target.edge] || vertex == graph.edgeB[target.edge] {
                let rest = vertex == graph.edgeA[target.edge]
                    ? target.alongFromA : graph.edgeLength[target.edge] - target.alongFromA
                let total = distance[vertex] + rest * scale(target) + target.distance
                if total < best {
                    best = total
                    bestEnd = (vertex, index)
                    bestShared = nil
                }
            }
            for index in graph.adjacencyStart[vertex]..<graph.adjacencyStart[vertex + 1] {
                let edge = graph.adjacentEdges[index]
                let next = graph.edgeA[edge] == vertex ? graph.edgeB[edge] : graph.edgeA[edge]
                if !done[next] {
                    push(next, distance[vertex] + cost(edge), edge: edge, from: vertex, source: viaSource[vertex])
                }
            }
        }

        if let shared = bestShared {
            let source = sources[shared.source], target = targets[shared.target]
            return [(source.edge, partial(source.edge, from: source.alongFromA, to: target.alongFromA,
                                          start: source.point, end: target.point))]
        }
        guard let end = bestEnd else { return nil }
        var chain: [(edge: Int, arrive: Int)] = []
        var vertex = end.vertex
        while viaEdge[vertex] != -1 {
            chain.append((viaEdge[vertex], vertex))
            vertex = viaVertex[vertex]
        }
        chain.reverse()
        let source = sources[viaSource[vertex]], target = targets[end.target]
        var pieces: [Piece] = []
        let leaveAt = vertex == graph.edgeA[source.edge] ? 0 : graph.edgeLength[source.edge]
        pieces.append((source.edge, partial(source.edge, from: source.alongFromA, to: leaveAt,
                                            start: source.point, end: nil)))
        for (edge, arrive) in chain {
            let points = graph.points(edge)
            pieces.append((edge, graph.edgeB[edge] == arrive ? points : points.reversed()))
        }
        let enterAt = end.vertex == graph.edgeA[target.edge] ? 0 : graph.edgeLength[target.edge]
        pieces.append((target.edge, partial(target.edge, from: enterAt, to: target.alongFromA,
                                            start: nil, end: target.point)))
        return pieces
    }
    // swiftlint:enable function_body_length cyclomatic_complexity

    /// Part of an edge from `from` to `to` metres along it (either direction), in walking order.
    private func partial(_ edge: Int, from: Double, to: Double, start: Coordinate?, end: Coordinate?) -> [Coordinate] {
        let shape = graph.points(edge)
        var along = [0.0]
        for (from, to) in zip(shape, shape.dropFirst()) { along.append(along[along.count - 1] + from.distance(to: to)) }
        let low = min(from, to), high = max(from, to)
        let forward = from <= to
        func point(at metres: Double, snapped: Coordinate?) -> Coordinate {
            if let snapped { return snapped }
            guard let index = along.firstIndex(where: { $0 >= metres }), index > 0 else { return shape[0] }
            let fraction = min(1, max(0, (metres - along[index - 1]) / max(along[index] - along[index - 1], 1e-6)))
            return shape[index - 1].interpolated(to: shape[index], fraction: fraction)
        }
        var result = [point(at: low, snapped: forward ? start : end)]
        for index in shape.indices where along[index] > low && along[index] < high { result.append(shape[index]) }
        result.append(point(at: high, snapped: forward ? end : start))
        return forward ? result : result.reversed()
    }
}

/// A binary min-heap of (priority, vertex) for the A* search.
struct MinHeap {
    private var items: [(priority: Double, vertex: Int)] = []

    mutating func push(_ priority: Double, _ vertex: Int) {
        items.append((priority, vertex))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].priority < items[parent].priority else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Int? {
        guard !items.isEmpty else { return nil }
        let top = items[0].vertex
        let last = items.removeLast()
        guard !items.isEmpty else { return top }
        items[0] = last
        var parent = 0
        while true {
            let left = 2 * parent + 1, right = left + 1
            var smallest = parent
            if left < items.count, items[left].priority < items[smallest].priority { smallest = left }
            if right < items.count, items[right].priority < items[smallest].priority { smallest = right }
            if smallest == parent { break }
            items.swapAt(parent, smallest)
            parent = smallest
        }
        return top
    }
}
