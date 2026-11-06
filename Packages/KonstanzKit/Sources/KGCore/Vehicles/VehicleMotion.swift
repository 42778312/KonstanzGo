import Foundation

/// Which way a vehicle is about to turn, for its indicators.
public enum VehicleTurn: Sendable, Hashable {
    case none, left, right
}

extension VehiclePosition {
    /// A bus signals a real corner, not the small bends of a road or pulling out of a stop.
    public var signal: VehicleTurn {
        guard line.mode == .bus, abs(turnAhead) >= VehicleMotion.signalDegrees else { return .none }
        return turnAhead > 0 ? .right : .left
    }
}

/// Turns each vehicle at the speed a real one can, so it swings through a corner instead of snapping round.
public struct VehicleMotion: Sendable {
    public static let turnDegreesPerSecond = 70.0
    static let signalDegrees = 25.0
    private var headings: [Int: Double] = [:]

    public init() {}

    /// The headings to show for `targets` (by trip) after `seconds`. A vehicle not seen before starts at its target;
    /// one no longer running is forgotten.
    public mutating func advance(_ targets: [Int: Double], after seconds: Double) -> [Int: Double] {
        let step = Self.turnDegreesPerSecond * seconds
        var next: [Int: Double] = [:]
        for (id, target) in targets {
            guard let current = headings[id] else {
                next[id] = target
                continue
            }
            let gap = Self.signedDifference(from: current, to: target)
            let heading = current + min(abs(gap), step) * (gap < 0 ? -1 : 1)
            next[id] = (heading + 360).truncatingRemainder(dividingBy: 360)
        }
        headings = next
        return next
    }

    /// The shortest way round from one compass heading to another: positive is clockwise, to the right.
    public static func signedDifference(from: Double, to: Double) -> Double {
        let gap = (to - from).truncatingRemainder(dividingBy: 360)
        return gap > 180 ? gap - 360 : gap <= -180 ? gap + 360 : gap
    }
}

/// A new report changes how late a bus is. Instead of jumping, the bus eases there: it slows right down for a bigger
/// delay and catches up at three times its speed for a smaller one. Only a big change, when a bus was first reported
/// or its report was far off, moves it at once.
public struct DelayGlide: Sendable {
    /// Delay seconds gained per second: the bus keeps creeping forward, never backwards.
    static let growing = 0.85
    /// Delay seconds lost per second.
    static let shrinking = 2.0
    static let snapSeconds = 45.0
    private var shown: [Int: Double] = [:]

    public init() {}

    /// The delays to place the buses by, on the way to `targets`, after `seconds`.
    public mutating func advance(_ targets: [Int: Double], after seconds: Double) -> [Int: Double] {
        var next: [Int: Double] = [:]
        for id in Set(targets.keys).union(shown.keys) {
            let target = targets[id] ?? 0, current = shown[id] ?? 0
            let gap = target - current
            let delay: Double
            if abs(gap) >= Self.snapSeconds {
                delay = target
            } else if gap > 0 {
                delay = min(target, current + Self.growing * seconds)
            } else {
                delay = max(target, current - Self.shrinking * seconds)
            }
            if delay != 0 || targets[id] != nil { next[id] = delay }
        }
        shown = next
        return next
    }
}
