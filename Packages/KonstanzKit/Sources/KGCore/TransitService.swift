import Foundation
import Synchronization

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
    private let notices = Mutex<[ServiceNotice]>([])

    /// Opens every data file; about a second on a phone, so the app does it behind the start animation.
    public init(data: BundledData) throws {
        let store = try TimetableStore(url: data.timetable)
        self.store = store
        // The two big files at the same time: this is what the app's start waits for.
        let graph = Mutex<Result<WalkGraph, any Error>?>(nil)
        let search = Mutex<Result<PlaceSearch, any Error>?>(nil)
        DispatchQueue.concurrentPerform(iterations: 2) { part in
            if part == 0 {
                let read = Result { try WalkGraph.read(from: data.walkGraph) }
                graph.withLock { $0 = read }
            } else {
                let read = Result { try PlaceSearch(indexURL: data.searchIndex, store: store) }
                search.withLock { $0 = read }
            }
        }
        guard let walkGraph = try graph.withLock({ $0 })?.get(), let places = try search.withLock({ $0 })?.get() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        walker = WalkRouter(graph: walkGraph)
        planner = try JourneyPlanner(store: store, url: data.timetable, walker: walker)
        placeSearch = places
        tracker = try VehicleTracker(store: store, url: data.timetable, streets: walker)
        lookup = ReverseLookup(walk: walker, store: store)
        timetableInfo = try? TimetableInfo.read(from: data.timetable)
    }

    /// The operator's disruptions, from `LiveModel`: closed stops leave routes and departures.
    public func update(notices new: [ServiceNotice]) {
        notices.withLock { $0 = new }
        planner.update(notices: new)
    }

    private func marked(_ departures: [Departure]) -> [Departure] {
        let known = notices.withLock { $0 }
        guard known.contains(where: \.closesStops) else { return departures }
        return departures.map { departure in
            var marked = departure
            if StopClosures(notices: known, at: departure.scheduled)
                .isClosed(station: departure.platform.stationID, line: departure.line.name) {
                marked.status = .stopClosed
            }
            return marked
        }
    }

    public var stations: [Station] { store.stations }
    public func station(id: Int) -> Station? { store.station(id: id) }

    public func stations(near point: Coordinate, within metres: Double, limit: Int) -> [(Station, Double)] {
        store.stations(near: point, within: metres, limit: limit)
    }

    public func departures(at stationID: Int, from date: Date, limit: Int) throws -> [Departure] {
        marked(try store.departures(at: stationID, from: date, limit: limit))
    }

    public func departuresByLine(at stationID: Int, from date: Date) throws -> [LineDirection] {
        try store.departuresByLine(at: stationID, from: date)
    }

    public func lines(at stationID: Int) throws -> [Line] { try store.lines(at: stationID) }
    public func trip(id: Int, on day: ServiceDay) throws -> Trip? { try store.trip(id: id, on: day) }
    public func plan(_ request: PlanRequest) throws -> [Journey] { try planner.plan(request) }
    public func plan(_ request: PlanRequest, live: LiveState) throws -> [Journey] { try planner.plan(request, live: live) }

    public func search(_ query: String, near point: Coordinate) -> [SearchResult] {
        placeSearch.search(query, near: point)
    }

    public func whereabouts(at point: Coordinate) -> Whereabouts {
        lookup.whereabouts(at: point, townFrom: placeSearch)
    }

    public func vehicles(at date: Date) throws -> [VehiclePosition] { try tracker.positions(at: date, cityOnly: true) }

    public func walk(from start: Coordinate, to end: Coordinate) -> WalkRoute? { walker.route(from: start, to: end) }
}
