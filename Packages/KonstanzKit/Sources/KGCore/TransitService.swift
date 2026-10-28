import Foundation

/// Everything the screens ask about buses and places. `OfflineTransit` answers from the bundled data;
/// `DesignSample` answers with the design's own examples, for previews and snapshot tests.
public protocol TransitService: Sendable {
    var stations: [Station] { get }
    var timetableInfo: TimetableInfo? { get }

    func station(id: Int) -> Station?
    func stations(near point: Coordinate, within metres: Double, limit: Int) -> [(Station, Double)]
    func departures(at stationID: Int, from date: Date, limit: Int) throws -> [Departure]
    func departuresByLine(at stationID: Int, from date: Date) throws -> [LineDirection]
    func lines(at stationID: Int) throws -> [Line]
    func trip(id: Int, on day: ServiceDay) throws -> Trip?
    func plan(_ request: PlanRequest) throws -> [Journey]
    func search(_ query: String, near point: Coordinate) -> [SearchResult]
    func whereabouts(at point: Coordinate) -> Whereabouts
    func vehicles(at date: Date) throws -> [VehiclePosition]
    func walk(from start: Coordinate, to end: Coordinate) -> WalkRoute?
}

/// The real thing: the offline timetable, planner, search, walking network and estimated vehicles.
public final class OfflineTransit: TransitService {
    public let store: TimetableStore
    public let planner: JourneyPlanner
    public let placeSearch: PlaceSearch
    public let walker: WalkRouter
    public let tracker: VehicleTracker
    public let timetableInfo: TimetableInfo?
    private let lookup: ReverseLookup

    /// Opens every data file; about a second on a phone, so the app does it behind the start animation.
    public init(data: BundledData) throws {
        store = try TimetableStore(url: data.timetable)
        walker = WalkRouter(graph: try WalkGraph.read(from: data.walkGraph))
        planner = try JourneyPlanner(store: store, url: data.timetable, walker: walker)
        placeSearch = try PlaceSearch(indexURL: data.searchIndex, store: store)
        tracker = try VehicleTracker(store: store, url: data.timetable)
        lookup = ReverseLookup(walk: walker, store: store)
        timetableInfo = try? TimetableInfo.read(from: data.timetable)
    }

    public var stations: [Station] { store.stations }
    public func station(id: Int) -> Station? { store.station(id: id) }

    public func stations(near point: Coordinate, within metres: Double, limit: Int) -> [(Station, Double)] {
        store.stations(near: point, within: metres, limit: limit)
    }

    public func departures(at stationID: Int, from date: Date, limit: Int) throws -> [Departure] {
        try store.departures(at: stationID, from: date, limit: limit)
    }

    public func departuresByLine(at stationID: Int, from date: Date) throws -> [LineDirection] {
        try store.departuresByLine(at: stationID, from: date)
    }

    public func lines(at stationID: Int) throws -> [Line] { try store.lines(at: stationID) }
    public func trip(id: Int, on day: ServiceDay) throws -> Trip? { try store.trip(id: id, on: day) }
    public func plan(_ request: PlanRequest) throws -> [Journey] { try planner.plan(request) }

    public func search(_ query: String, near point: Coordinate) -> [SearchResult] {
        placeSearch.search(query, near: point)
    }

    public func whereabouts(at point: Coordinate) -> Whereabouts {
        lookup.whereabouts(at: point, townFrom: placeSearch)
    }

    public func vehicles(at date: Date) throws -> [VehiclePosition] { try tracker.positions(at: date, cityOnly: true) }

    public func walk(from start: Coordinate, to end: Coordinate) -> WalkRoute? { walker.route(from: start, to: end) }
}
