import Foundation
import Testing
@testable import KGCore

/// Against the real bundled timetable (feed 20261011). Numbers here change with a new feed.
@Suite("Timetable store")
struct TimetableStoreTests {
    let store: TimetableStore
    let clock = ServiceClock()
    let sternenplatz = 99
    let universitaet = 3  // "Egg/Universität"

    init() throws {
        store = try TimetableStore(url: repoData.timetable)
    }

    func at(_ yyyymmdd: Int, _ hour: Int, _ minute: Int) -> Date {
        clock.date(ServiceDay(yyyymmdd: yyyymmdd), minutes: hour * 60 + minute)
    }

    @Test func loadsEverythingSmallUpFront() {
        #expect(store.stations.count == 142)
        #expect(store.lines.count == 47)
        #expect(store.station(id: sternenplatz)?.shortName == "Sternenplatz")
        #expect(store.platforms(of: sternenplatz).count == 3)  // 98 "Sternenplatz/Spanierstraße" is its own station
    }

    @Test func emptyPlatformCodesBecomeNil() {
        let codes = store.platforms(of: sternenplatz).map(\.code)
        #expect(codes.contains(nil))
        #expect(codes.contains("1"))
        #expect(!codes.contains(""))
    }

    @Test func departuresAreInOrderAndNotBeforeTheTime() throws {
        let from = at(20261028, 14, 0)
        let departures = try store.departures(at: sternenplatz, from: from, limit: 30)
        #expect(departures.count == 30)
        #expect(departures.allSatisfy { $0.scheduled >= from })
        #expect(departures.map(\.scheduled) == departures.map(\.scheduled).sorted())
        #expect(departures.allSatisfy { $0.status == .scheduled })
        #expect(Set(departures.map(\.line.name)).isSuperset(of: ["1", "5", "9"]))
    }

    @Test func arrivalsAtTheLastStopAreNotDepartures() throws {
        let departures = try store.departures(at: sternenplatz, from: at(20261028, 6, 0), limit: 400, within: 18)
        #expect(!departures.isEmpty)
        #expect(!departures.contains { $0.headsign == "Sternenplatz" && $0.line.name == "12" })
    }

    @Test func headsignsAreShortened() throws {
        let departures = try store.departures(at: sternenplatz, from: at(20261028, 14, 0), limit: 60)
        #expect(departures.contains { $0.line.name == "9" && $0.headsign == "Universität" })
        #expect(!departures.contains { $0.headsign.hasPrefix("Konstanz ") })
        #expect(store.displayName(headsign: "Friedrichshafen Hafenbahnhof") == "Friedrichshafen Hafenbahnhof")
        #expect(store.displayName(headsign: "Konstanz, Zähringerplatz") == "Zähringerplatz")
    }

    @Test func afterMidnightYesterdaysNightBusesStillShow() throws {
        // A Wednesday night: at 00:05 on Thu 29 Oct, buses of the 28th's service day are still due.
        let departures = try store.departures(at: 15, from: at(20261029, 0, 5), limit: 10, within: 3)
        let latest = departures.map(\.scheduled).max()
        #expect(departures.allSatisfy { $0.scheduled >= at(20261029, 0, 5) })
        #expect(latest != nil)
    }

    /// At 23:30 the next day's service is already in view: the S14 at 00:09 on 6 Nov belongs to the 6th.
    @Test func lateInTheEveningTheNextServiceDaysDeparturesShow() throws {
        let from = at(20261105, 23, 30)
        let departures = try store.departures(at: 15, from: from, limit: 60)
        #expect(departures.contains { $0.line.name == "S14" && $0.scheduled == at(20261106, 0, 9) })
        #expect(departures.allSatisfy { $0.scheduled >= from })
        #expect(departures.map(\.scheduled) == departures.map(\.scheduled).sorted())
    }

    @Test func nextDirectBusLooksAtTonightsTripsOfTomorrow() throws {
        let kreuzlingen = 108
        let next = try #require(try store.nextDirectDeparture(from: 15, to: kreuzlingen, after: at(20261106, 0, 0).addingTimeInterval(-60)))
        #expect(next.departure.scheduled == at(20261106, 0, 9))
    }

    @Test func middayStillListsOnlyWhatIsInTheWindow() throws {
        let departures = try store.departures(at: 15, from: at(20261105, 12, 0), limit: 400, within: 2)
        #expect(!departures.isEmpty)
        #expect(departures.allSatisfy { $0.scheduled < at(20261105, 14, 0) })
    }

    @Test func noDeparturesAfterTheTimetableEnds() throws {
        #expect(try store.departures(at: sternenplatz, from: at(20261220, 12, 0)).isEmpty)
    }

    @Test func groupsByLineAndDirection() throws {
        let groups = try store.departuresByLine(at: sternenplatz, from: at(20261028, 14, 0))
        #expect(!groups.isEmpty)
        #expect(groups.allSatisfy { !$0.departures.isEmpty && $0.departures.count <= 3 })
        #expect(groups.allSatisfy { group in group.departures.allSatisfy { $0.headsign == group.headsign } })
        let names = groups.map(\.line.name)
        #expect(names == names.sorted { LineOrder.precedes($0, $1) || $0 == $1 })
    }

    @Test func linesAtAStationInBadgeOrder() throws {
        let names = try store.lines(at: sternenplatz).map(\.name)
        #expect(Array(names.prefix(6)) == ["1", "2", "3", "4", "4/13", "5"])  // combined lines follow their first number
        #expect(names.contains("9") && names.contains("N"))
    }

    @Test func tripHasAllStopsInOrderAndAShape() throws {
        let departure = try #require(try store.departures(at: sternenplatz, from: at(20261028, 14, 0))
            .first { $0.line.name == "9" })
        let trip = try #require(try store.trip(id: departure.tripID, on: ServiceDay(yyyymmdd: 20261028)))
        #expect(trip.line.name == "9")
        #expect(trip.stops.count > 5)
        #expect(trip.stops.map(\.departure) == trip.stops.map(\.departure).sorted())
        #expect(trip.stops.contains { $0.station.id == sternenplatz && $0.departure == departure.scheduled })
        #expect(trip.shape.count > 10)
        // The shape stays in the Konstanz area.
        #expect(trip.shape.allSatisfy { (47.6...47.75).contains($0.latitude) && (9.0...9.3).contains($0.longitude) })
    }

    @Test func firstDirectBusOfTheDay() throws {
        let first = try #require(try store.firstDirectDeparture(from: sternenplatz, to: universitaet,
                                                                 on: ServiceDay(yyyymmdd: 20261029)))
        #expect(first.scheduled > at(20261029, 4, 0) && first.scheduled < at(20261029, 8, 0))
        let earlier = try store.departures(at: sternenplatz, from: at(20261029, 0, 0), limit: 200, within: 24)
            .filter { $0.scheduled < first.scheduled && $0.headsign == "Universität" }
        #expect(earlier.isEmpty, "a direct bus to Universität leaves earlier: \(earlier.first?.scheduled as Any)")
    }

    @Test func lineOrderIsNumericThenSuffix() {
        let sorted = ["12", "N", "9A", "1", "9", "CS", "5", "12/3"].sorted(by: LineOrder.precedes)
        #expect(sorted == ["1", "5", "9", "9A", "12", "12/3", "CS", "N"])
    }

    @Test func polylineDecodesGooglesExample() {
        // From Google's documentation.
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(points.count == 3)
        #expect(abs(points[0].latitude - 38.5) < 1e-9 && abs(points[0].longitude - -120.2) < 1e-9)
        #expect(abs(points[2].latitude - 43.252) < 1e-9 && abs(points[2].longitude - -126.453) < 1e-9)
    }

    @Test func departuresQueryIsFast() throws {
        let start = Date()
        for hour in 6..<22 {
            _ = try store.departures(at: sternenplatz, from: at(20261028, hour, 0))
        }
        let perQuery = Date().timeIntervalSince(start) / 16
        #expect(perQuery < 0.02, "\(Int(perQuery * 1000)) ms per query")
    }

    @Test func nextDirectBusBetweenTwoStops() throws {
        let universitaet = try #require(store.stations.first { $0.shortName == "Universität" })
        let next = try #require(try store.nextDirectDeparture(from: sternenplatz, to: universitaet.id,
                                                              after: at(20261028, 14, 0)))
        #expect(next.departure.scheduled >= at(20261028, 14, 0))
        #expect(next.arrival > next.departure.scheduled)
        #expect(next.arrival.timeIntervalSince(next.departure.scheduled) < 3600)
    }
}
