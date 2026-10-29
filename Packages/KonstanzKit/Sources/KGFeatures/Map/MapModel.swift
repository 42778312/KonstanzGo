import CoreGraphics
import Foundation
import KGCore
import Observation

/// What the map shows and where it looks; the screens change it, the map view follows it.
@MainActor
@Observable
public final class MapModel {
    /// Stops drawn as a map layer (plan M4).
    public var stations: [Station] = []
    public var selectedStationID: Int?
    /// Route lines (plan M7): bus parts coral with a white casing, walking parts dotted.
    public var lines: [MapLine] = []
    /// Points that SwiftUI draws over the map (buses, start and end markers), by id.
    public var pins: [MapPin] = []
    public private(set) var pinPoints: [String: CGPoint] = [:]
    /// The user's position, when known.
    public var userLocation: Coordinate?
    public var userHeading: Double?

    /// Where overlay views go, in the map's points; updated by the map as it moves.
    public private(set) var userPoint: CGPoint?
    public private(set) var selectedPoint: CGPoint?
    /// Space the sheet and the search bar take, so the camera keeps things visible (plan M9).
    public var insets = MapInsets()

    /// A camera move for the map view to run once.
    public private(set) var pendingMove: CameraMove?
    /// Called when a stop on the map is tapped.
    public var onSelectStation: ((Station) -> Void)?
    /// Called on a long press on the map (drop a pin, plan M8).
    public var onLongPress: ((Coordinate) -> Void)?
    /// The middle of the visible map after the last move.
    public var centerCoordinate: Coordinate?

    public init() {}

    public func move(_ move: CameraMove) {
        pendingMove = move
    }

    /// A zoom step for the map view to run once (+ / − buttons).
    public private(set) var pendingZoom: Double?

    public func zoom(by step: Double) {
        pendingZoom = step
    }

    func takePendingZoom() -> Double? {
        defer { pendingZoom = nil }
        return pendingZoom
    }

    func takePendingMove() -> CameraMove? {
        defer { pendingMove = nil }
        return pendingMove
    }

    func setOverlayPoints(user: CGPoint?, selected: CGPoint?, pins: [String: CGPoint]) {
        if userPoint != user { userPoint = user }
        if selectedPoint != selected { selectedPoint = selected }
        if pinPoints != pins { pinPoints = pins }
    }

    public var selectedStation: Station? {
        guard let selectedStationID else { return nil }
        return stations.first { $0.id == selectedStationID }
    }
}

/// Edges of the map covered by other views, in points.
public struct MapInsets: Equatable, Sendable {
    public var top: CGFloat = 0
    public var bottom: CGFloat = 0

    public init(top: CGFloat = 0, bottom: CGFloat = 0) {
        self.top = top
        self.bottom = bottom
    }
}

/// A camera change the map runs: fly to a point at a zoom, or fit points into the view, keeping the insets
/// clear.
public struct CameraMove: Equatable, Sendable {
    public var center: Coordinate
    public var zoom: Double
    public var animated: Bool
    /// When set, the camera shows all of these instead (route on map).
    public var fit: [Coordinate]

    public init(center: Coordinate, zoom: Double, animated: Bool = true) {
        self.center = center
        self.zoom = zoom
        self.animated = animated
        fit = []
    }

    public static func fitting(_ points: [Coordinate], animated: Bool = true) -> CameraMove {
        var move = CameraMove(center: points.first ?? MapRegion.center, zoom: MapRegion.startZoom, animated: animated)
        move.fit = points
        return move
    }
}

/// A line on the map.
public struct MapLine: Hashable, Sendable {
    public enum Kind: String, Sendable { case bus, walk }

    public var kind: Kind
    public var points: [Coordinate]

    public init(kind: Kind, points: [Coordinate]) {
        self.kind = kind
        self.points = points
    }
}

/// A point the screen draws a view on (a bus, a start or end marker).
public struct MapPin: Hashable, Sendable, Identifiable {
    public var id: String
    public var coordinate: Coordinate

    public init(id: String, coordinate: Coordinate) {
        self.id = id
        self.coordinate = coordinate
    }
}
