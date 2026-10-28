import Foundation

/// A point on Earth in degrees (WGS 84), as stored in the timetable and the map data.
public struct Coordinate: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine; under 0.5 % error at Konstanz's scale).
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let haversine = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(haversine)))
    }

    /// The point `fraction` (0…1) of the way towards `other`, on a straight line.
    public func interpolated(to other: Coordinate, fraction: Double) -> Coordinate {
        Coordinate(latitude: latitude + (other.latitude - latitude) * fraction,
                   longitude: longitude + (other.longitude - longitude) * fraction)
    }

    /// Compass bearing towards `other` in degrees, 0 = north, clockwise.
    public func bearing(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Walking speed and detour used everywhere a walking time is estimated or routed.
/// Same values as the Android app, so both give the same journeys.
public enum Walking {
    /// 4.8 km/h.
    public static let metresPerMinute = 80.0
    /// Streets are not straight: a walk is about 1.25 × the straight-line distance.
    public static let detour = 1.25

    /// Estimated walking metres between two points when no street path is known.
    public static func estimatedMetres(from: Coordinate, to: Coordinate) -> Double {
        from.distance(to: to) * detour
    }

    /// Whole minutes to walk `metres`, at least 1.
    public static func minutes(forMetres metres: Double) -> Int {
        max(1, Int((metres / metresPerMinute).rounded(.up)))
    }
}
