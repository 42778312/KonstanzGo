import Foundation

/// Fitting stops onto a trip's shape (the road it drives). Same rules as the Android app.
public enum Shapes {
    /// Points at most this far apart after `densify` (metres).
    public static let step = 12.0
    /// A stop this close to the shape counts as on it (metres).
    public static let radius = 50.0

    /// `points` with extra points so no two are more than `maxStep` metres apart. Shapes are simplified to a few
    /// points per straight street; a stop halfway along one is only near the shape once it has points there.
    public static func densify(_ points: [Coordinate], maxStep: Double = step) -> [Coordinate] {
        guard points.count >= 2 else { return points }
        var result = [points[0]]
        for (from, to) in zip(points, points.dropFirst()) {
            let pieces = max(1, Int((from.distance(to: to) / maxStep).rounded(.up)))
            for piece in 1...pieces {
                result.append(from.interpolated(to: to, fraction: Double(piece) / Double(pieces)))
            }
        }
        return result
    }

    /// For each stop, the index of its point on `shape`, walking forward stop by stop. A stop takes the *first*
    /// pass of the shape within `radius` after the previous stop: ring and out-and-back lines pass the same street
    /// twice, and the nearest point overall can be a later pass, which would skip a whole loop. Only when no pass
    /// comes that close does it take the nearest point ahead. nil when the shape is empty.
    public static func match(_ stops: [Coordinate], to shape: [Coordinate], within radius: Double = radius) -> [Int]? {
        guard !shape.isEmpty else { return nil }
        var index = 0
        var matched: [Int] = []
        for stop in stops {
            var cursor = index
            while cursor < shape.count, shape[cursor].distance(to: stop) > radius { cursor += 1 }
            if cursor < shape.count {
                // The closest point of this pass.
                var best = cursor
                while cursor < shape.count, shape[cursor].distance(to: stop) <= radius {
                    if shape[cursor].distance(to: stop) < shape[best].distance(to: stop) { best = cursor }
                    cursor += 1
                }
                index = best
            } else {
                index = (index..<shape.count)
                    .min { shape[$0].distance(to: stop) < shape[$1].distance(to: stop) } ?? index
            }
            matched.append(index)
        }
        return matched
    }

    /// The road between two stops of a trip: the matched piece of the shape, or nil when it is implausible
    /// (more than 1.8 × the straight line plus 200 m: the wrong street or a loop the bus does not drive).
    public static func piece(of shape: [Coordinate], from: Int, to: Int, between start: Coordinate,
                             and end: Coordinate) -> [Coordinate]? {
        guard to > from, from >= 0, to < shape.count else { return nil }
        let piece = Array(shape[from...to])
        let length = zip(piece, piece.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        return length <= 1.8 * start.distance(to: end) + 200 ? piece : nil
    }
}
