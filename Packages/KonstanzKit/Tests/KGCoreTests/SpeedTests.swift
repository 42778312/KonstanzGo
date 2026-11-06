import Foundation
import Testing
@testable import KGCore

/// How long the things the user waits for take, on the real data. The limits are for a Mac and leave room for a
/// phone (roughly 3 times slower): over them, a screen would visibly wait. The times are printed for the record.
@Suite("Speed", .serialized)
struct SpeedTests {
    let clock = ServiceClock()

    func midday() -> Date { clock.date(ServiceDay(yyyymmdd: 20261106), minutes: 12 * 60) }

    func time(_ name: String, limit: Duration, runs: Int = 20, _ work: () throws -> Void) rethrows {
        let watch = ContinuousClock()
        var worst = Duration.zero, total = Duration.zero
        for _ in 0..<runs {
            let took = try watch.measure(work)
            total += took
            worst = max(worst, took)
        }
        let average = total / runs
        print("SPEED \(name): average \(average), worst \(worst)")
        // A Debug build runs many times slower than what people get; only Release numbers mean anything here.
        #expect(average < (_isDebugAssertConfiguration() ? limit * 40 : limit), "\(name) took \(average)")
    }

    @Test func openingAllTheData() throws {
        try time("open all offline data", limit: .milliseconds(700), runs: 3) { _ = try OfflineTransit(data: repoData) }
    }

    @Test func whatOpeningSpendsItsTimeOn() throws {
        let store = try TimetableStore(url: repoData.timetable)
        try time("  timetable store", limit: .milliseconds(100), runs: 3) { _ = try TimetableStore(url: repoData.timetable) }
        try time("  search index", limit: .milliseconds(400), runs: 3) { _ = try PlaceSearch(indexURL: repoData.searchIndex, store: store) }
        try time("  walking network", limit: .milliseconds(300), runs: 3) { _ = try WalkGraph.read(from: repoData.walkGraph) }
        try time("  planner", limit: .milliseconds(100), runs: 3) { _ = try JourneyPlanner(store: store, url: repoData.timetable) }
    }

    @Test func aStopsDepartures() throws {
        let store = try TimetableStore(url: repoData.timetable)
        try time("departures at Bahnhof", limit: .milliseconds(10)) {
            _ = try store.departures(at: 15, from: midday(), limit: 60)
        }
    }

    @Test func planningARoute() throws {
        let store = try TimetableStore(url: repoData.timetable)
        let planner = try JourneyPlanner(store: store, url: repoData.timetable)
        let from = try #require(store.station(id: 99)), to = try #require(store.station(id: 3))
        let request = PlanRequest(from: Endpoint(name: from.name, coordinate: from.coordinate),
                                  to: Endpoint(name: to.name, coordinate: to.coordinate), time: midday())
        try time("first route of the day (builds the day)", limit: .milliseconds(150), runs: 1) { _ = try planner.plan(request) }
        try time("next route", limit: .milliseconds(25)) { _ = try planner.plan(request) }
    }

    @Test func busesOnTheMap() throws {
        let store = try TimetableStore(url: repoData.timetable)
        let tracker = try VehicleTracker(store: store, url: repoData.timetable)
        _ = try tracker.positions(at: midday())
        try time("all bus positions (runs 4 times a second)", limit: .milliseconds(10), runs: 40) {
            _ = try tracker.positions(at: midday())
        }
    }

    @Test func searching() throws {
        let transit = try OfflineTransit(data: repoData)
        // The very first search may wait for the index, which reads in the background after the app opens.
        time("first search right after opening", limit: .seconds(1), runs: 1) { _ = transit.search("sternenpl", near: PlaceSearch.konstanzCentre) }
        time("search per letter", limit: .milliseconds(15)) { _ = transit.search("sternenpl", near: PlaceSearch.konstanzCentre) }
    }

    @Test func readingLiveDepartures() throws {
        let store = try TimetableStore(url: repoData.timetable)
        let departures = try store.departures(at: 15, from: midday(), limit: 60)
        let events = departures.map { LiveEvent(line: $0.line.name, planned: $0.scheduled, platform: $0.platform.gtfsID, delay: 120) }
        time("putting live reports on the timetable", limit: .milliseconds(2)) { _ = EFADepartures.merge(departures, with: events) }
    }
}
