import Foundation

/// What is at a point on the map (screen 16, "Pin gesetzt"): the street, the area, and the nearest station.
public struct Whereabouts: Sendable, Hashable {
    /// Nearest named street within 60 m, "Seestraße"; nil in a park or on the lake.
    public var street: String?
    /// Town, "Konstanz" (from the nearest place's area).
    public var town: String?
    public var coordinate: Coordinate
    public var nearestStation: Station?
    /// Walking minutes to it (straight-line estimate).
    public var walkMinutes: Int?
}

/// Reverse lookup on the offline data.
public struct ReverseLookup: Sendable {
    public static let streetRadius = 60.0
    public static let stationRadius = 1_500.0

    private let walk: WalkRouter
    private let store: TimetableStore

    public init(walk: WalkRouter, store: TimetableStore) {
        self.walk = walk
        self.store = store
    }

    public func whereabouts(at point: Coordinate, townFrom search: PlaceSearch? = nil) -> Whereabouts {
        let station = store.stations(near: point, within: Self.stationRadius, limit: 1).first
        return Whereabouts(
            street: street(near: point),
            town: search.flatMap { town(near: point, search: $0) },
            coordinate: point,
            nearestStation: station?.0,
            walkMinutes: station.map { Walking.minutes(forMetres: $0.1 * Walking.detour) }
        )
    }

    /// The nearest named way: candidate ways near the point first, then the grid cells around it.
    public func street(near point: Coordinate) -> String? {
        let graph = walk.graph
        let centre = WalkGraph.cell(point.latitude, point.longitude)
        var best: (name: String, distance: Double)?
        for y in (centre.y - 1)...(centre.y + 1) {
            for x in (centre.x - 1)...(centre.x + 1) {
                for edge in graph.cells[WalkGraph.key(y, x)] ?? [] {
                    guard let name = graph.name(of: edge) else { continue }
                    let shape = graph.points(edge)
                    for (from, to) in zip(shape, shape.dropFirst()) {
                        let onSegment = from.interpolated(to: to, fraction: WalkRouter.project(point, from, to))
                        let distance = point.distance(to: onSegment)
                        if distance <= Self.streetRadius, distance < best?.distance ?? .infinity {
                            best = (name, distance)
                        }
                    }
                }
            }
        }
        return best?.name
    }

    /// The town part of the nearest search entry's area ("Altstadt, Konstanz" → "Konstanz").
    private func town(near point: Coordinate, search: PlaceSearch) -> String? {
        search.nearest(to: point).flatMap { place in
            place.area.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }
}

extension PlaceSearch {
    /// The nearest place, street or address (not stations), for naming a point.
    public func nearest(to point: Coordinate) -> Place? {
        var best: (Place, Double)?
        for entry in entriesForLookup {
            guard case let .place(place) = entry.target else { continue }
            let distance = point.distance(to: place.coordinate)
            if distance < best?.1 ?? .infinity { best = (place, distance) }
        }
        return best?.0
    }
}
