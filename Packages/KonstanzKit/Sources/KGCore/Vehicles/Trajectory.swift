import Foundation

/// A vehicle at one moment: where it is and which way it heads (degrees from north, clockwise).
public struct VehiclePosition: Sendable, Hashable, Identifiable {
    public var tripID: Int
    public var line: Line
    public var headsign: String
    public var coordinate: Coordinate
    public var heading: Double
    /// Always estimated from the timetable for now (no live feed); shown as "geschätzt".
    public var isEstimated: Bool

    public var id: Int { tripID }
}

/// One trip's run as a path with times: where the bus is at any second. Times are seconds from midnight of
/// the day shown (a trip of yesterday's service runs at negative times).
///
/// Between two stops it drives like a bus: pulls away, cruises and brakes into the next stop (`rampSeconds`
/// each way), then waits briefly (`dwellSeconds`) where the timetable gives no wait. Same as the Android app.
/// A stop of a trip with its timetable times (minutes of its service day), for building a trajectory.
public struct TimedStop: Sendable, Hashable {
    public var coordinate: Coordinate
    public var arrival: Int
    public var departure: Int

    public init(coordinate: Coordinate, arrival: Int, departure: Int) {
        self.coordinate = coordinate
        self.arrival = arrival
        self.departure = departure
    }
}

public struct Trajectory: Sendable {
    public static let rampSeconds = 12.0
    public static let dwellSeconds = 15.0
    /// How far a passing time may move to even out speeds: the timetable's minute rounding.
    static let roundingSeconds = 30.0
    static let balancePasses = 8
    /// Metres behind and ahead that give the heading, so corners turn the arrow smoothly.
    static let headingSpan = 15.0

    public let tripID: Int
    public let line: Line
    public let headsign: String
    let path: [Coordinate]
    let cumulative: [Double]
    let callDistance: [Double]
    let arrival: [Double]
    let departure: [Double]
    let ramp: [Double]

    /// On the map from its first arrival to its last.
    public var start: Double { arrival[0] }
    public var end: Double { arrival[arrival.count - 1] }

    /// A trip's trajectory from its calls (position, arrival and departure in timetable minutes of its service
    /// day). Each stretch follows the shape when it fits, else goes straight. `shiftSeconds` moves the times onto
    /// the day shown (−86 400 for yesterday's service).
    public init?(tripID: Int, line: Line, headsign: String,
                 calls: [TimedStop],
                 shape: [Coordinate], shiftSeconds: Double = 0) {
        guard calls.count >= 2 else { return nil }
        let stops = calls.map(\.coordinate)
        let dense = Shapes.densify(shape)
        let matched = dense.count >= 2 ? Shapes.match(stops, to: dense) : nil
        let topSpeed = line.mode.topSpeedKmh / 3.6

        var path = [stops[0]]
        var distances = [0.0]
        var length = 0.0
        func add(_ point: Coordinate) {
            length += path[path.count - 1].distance(to: point)
            path.append(point)
        }
        for index in 1..<stops.count {
            let seconds = Double(calls[index].arrival - calls[index - 1].departure) * 60
            if let matched,
               let piece = Shapes.piece(of: dense, from: matched[index - 1], to: matched[index],
                                        between: stops[index - 1], and: stops[index]) {
                // The street path only when it is drivable in the time the timetable gives.
                let pieceLength = zip(piece, piece.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
                let straight = stops[index - 1].distance(to: stops[index])
                if seconds <= 0 || pieceLength / seconds <= topSpeed || straight / seconds > topSpeed {
                    piece.forEach(add)
                }
            }
            add(stops[index])
            distances.append(length)
        }

        var arrival = calls.map { Double($0.arrival) * 60 + shiftSeconds }
        var departure = calls.map { Double($0.departure) * 60 + shiftSeconds }
        Self.smoothTimes(arrival: &arrival, departure: &departure, distance: distances, topSpeed: topSpeed)

        self.tripID = tripID
        self.line = line
        self.headsign = headsign
        self.path = path
        var cumulative = [0.0]
        for (from, to) in zip(path, path.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + from.distance(to: to))
        }
        self.cumulative = cumulative
        callDistance = distances
        self.arrival = arrival
        self.departure = departure
        ramp = distances.indices.map { index in
            index == 0 ? 0 : Self.ramp(from: departure[index - 1], to: arrival[index],
                                       distance: distances[index] - distances[index - 1], topSpeed: topSpeed)
        }
    }

    /// Where the vehicle is at `seconds`: waiting at a stop between its arrival and departure, otherwise on
    /// the way to the next one. nil when the trip is not running then.
    public func position(at seconds: Double) -> VehiclePosition? {
        guard seconds >= start, seconds <= end else { return nil }
        var distance = callDistance[callDistance.count - 1]
        for index in arrival.indices where seconds <= departure[index] {
            if seconds >= arrival[index] || index == 0 {
                distance = callDistance[index]
            } else {
                let leave = departure[index - 1]
                let share = Self.travelled(seconds - leave, duration: arrival[index] - leave, ramp: ramp[index])
                distance = callDistance[index - 1] + share * (callDistance[index] - callDistance[index - 1])
            }
            break
        }
        let back = point(at: distance - Self.headingSpan), ahead = point(at: distance + Self.headingSpan)
        return VehiclePosition(tripID: tripID, line: line, headsign: headsign, coordinate: point(at: distance),
                               heading: back.distance(to: ahead) < 0.5 ? 0 : back.bearing(to: ahead),
                               isEstimated: true)
    }

    private func point(at distance: Double) -> Coordinate {
        guard path.count > 1, let total = cumulative.last else { return path[0] }
        let target = min(max(distance, 0), total)
        var low = 0, high = path.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= target { low = mid } else { high = mid }
        }
        let length = cumulative[high] - cumulative[low]
        let fraction = length <= 0 ? 0 : min(1, max(0, (target - cumulative[low]) / length))
        return path[low].interpolated(to: path[high], fraction: fraction)
    }

    // MARK: Motion

    /// Share of a stretch covered `time` seconds into a drive of `duration`: speeding up for `ramp` seconds,
    /// cruising, slowing down for as long (a smooth S-curve on short hops).
    public static func travelled(_ time: Double, duration: Double, ramp rampSeconds: Double = rampSeconds) -> Double {
        guard duration > 0 else { return 1 }
        let time = min(max(time, 0), duration)
        let ramp = min(rampSeconds, duration / 2)
        guard ramp > 0 else { return time / duration }
        let peak = 1 / (duration - ramp)
        let share: Double
        if time < ramp {
            share = 0.5 * peak * time * time / ramp
        } else if time > duration - ramp {
            share = 1 - 0.5 * peak * (duration - time) * (duration - time) / ramp
        } else {
            share = peak * (time - ramp / 2)
        }
        return min(1, max(0, share))
    }

    /// The ramp for a stretch: `rampSeconds`, or less so the peak speed stays within the vehicle's top speed.
    static func ramp(from: Double, to: Double, distance: Double, topSpeed: Double) -> Double {
        let duration = to - from
        guard duration > 0 else { return 0 }
        let room = duration * (1 - distance / duration / topSpeed)
        return max(0, min(rampSeconds, duration / 2, room))
    }

    // swiftlint:disable cyclomatic_complexity
    /// Times a bus can drive. The timetable rounds to minutes, so neighbouring stops often share one: a run of
    /// stops at the same minute is spread by distance; passing times then shift by up to half a minute so
    /// neighbouring stretches get similar speeds; then each stop without a wait gets a short one.
    /// Only the animation uses these times; departure boards keep the timetable's.
    static func smoothTimes(arrival at: inout [Double], departure leave: inout [Double], distance: [Double],
                            topSpeed: Double) {
        let count = at.count
        var first = 0
        while first < count {
            var last = first
            while last + 1 < count, at[last + 1] <= leave[first] { last += 1 }
            if last > first {
                if last + 1 < count {
                    // Stops first...last at one time: spread them from leave[first] towards at[last + 1].
                    let from = leave[first], to = at[last + 1]
                    let span = distance[last + 1] - distance[first] > 0 ? distance[last + 1] - distance[first] : 1
                    for index in (first + 1)...last {
                        let time = from + (to - from) * (distance[index] - distance[first]) / span
                        at[index] = time
                        leave[index] = max(leave[index], time)
                    }
                } else if first > 0 {
                    // The trip ends with them: spread back from the stop before.
                    let from = leave[first - 1], to = at[last]
                    let span = distance[last] - distance[first - 1] > 0 ? distance[last] - distance[first - 1] : 1
                    for index in first..<last {
                        let time = from + (to - from) * (distance[index] - distance[first - 1]) / span
                        at[index] = time
                        leave[index] = time
                    }
                }
            }
            first = last + 1
        }
        guard count > 2 else { return }
        let rounded = at
        for _ in 0..<balancePasses {
            for index in 1..<(count - 1) where leave[index] - at[index] <= 1 {
                let span = distance[index + 1] - distance[index - 1]
                guard span > 0 else { continue }
                let even = leave[index - 1] + (at[index + 1] - leave[index - 1])
                    * (distance[index] - distance[index - 1]) / span
                let time = min(max(min(max(even, rounded[index] - roundingSeconds), rounded[index] + roundingSeconds),
                                   leave[index - 1]), at[index + 1])
                at[index] = time
                leave[index] = time
            }
        }
        for index in 1..<(count - 1) where leave[index] - at[index] < dwellSeconds {
            // Arrive a little early, but leave enough time to drive the stretch at a real speed.
            let drive = max((leave[index] - leave[index - 1]) * 0.6, (distance[index] - distance[index - 1]) / topSpeed)
            let earliest = min(leave[index - 1] + drive, at[index])
            at[index] = max(min(at[index], leave[index] - dwellSeconds), earliest)
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
