import Foundation
import KGCore
import KGDesign
import Observation

/// Opens the offline data off the main thread while the start animation plays (plan S1.2).
@MainActor
@Observable
public final class TransitLoader {
    public private(set) var transit: OfflineTransit?
    public private(set) var failed = false
    let data: BundledData?

    public init(data: BundledData?) {
        self.data = data
        guard let data else {
            failed = true
            return
        }
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { try? OfflineTransit(data: data) }.value
            self.transit = loaded
            self.failed = loaded == nil
        }
    }
}

/// The stops around a point with their next departures, for the map's sheet (plan S4.5). Refreshes every
/// 30 s while the map is visible, and when the point moves.
@MainActor
@Observable
public final class NearbyModel {
    public struct Stop: Identifiable, Sendable {
        public var station: Station
        public var metres: Double
        public var departures: [KGDepartureItem]
        public var id: Int { station.id }

        /// Walking time at 4.8 km/h on a path about a quarter longer than the straight line.
        public var walkMinutes: Int { max(1, Int((metres * 1.25 / 80).rounded(.up))) }
    }

    public private(set) var stops: [Stop] = []
    public private(set) var selected: Stop?
    public private(set) var isLoading = true
    public private(set) var now = Date.now

    private let transit: TransitService
    private var point: Coordinate?

    /// How far to look and how many stops to keep.
    static let radius = 1_500.0
    static let count = 6

    public init(transit: TransitService) {
        self.transit = transit
    }

    public func update(around newPoint: Coordinate) {
        if let point, point.distance(to: newPoint) < 30, !stops.isEmpty { return }
        point = newPoint
        refresh()
    }

    public func select(_ station: Station?) {
        guard let station else {
            selected = nil
            return
        }
        let metres = point.map { station.coordinate.distance(to: $0) } ?? 0
        selected = Stop(station: station, metres: metres, departures: departures(at: station, limit: 6))
    }

    public func refresh() {
        now = .now
        guard let point else { return }
        stops = transit.stations(near: point, within: Self.radius, limit: Self.count).map { station, metres in
            Stop(station: station, metres: metres, departures: departures(at: station, limit: 3))
        }
        if let selected { select(selected.station) }
        isLoading = false
    }

    private func departures(at station: Station, limit: Int) -> [KGDepartureItem] {
        let list = (try? transit.departures(at: station.id, from: now, limit: limit)) ?? []
        return list.map { departure in
            KGDepartureItem(id: departure.id, line: departure.line.name, destination: departure.headsign,
                            platform: departure.platform.code, departure: departure.expected,
                            isLive: departure.status.isLive)
        }
    }
}
