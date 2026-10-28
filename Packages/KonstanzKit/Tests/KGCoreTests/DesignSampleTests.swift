import Foundation
import Testing
@testable import KGCore

/// The sample must show exactly the design's numbers; screens and snapshot tests rely on it.
@Suite("Design sample")
struct DesignSampleTests {
    let sample = DesignSample()
    let now = DesignSample.now

    func minutes(_ date: Date) -> Int { Int((date.timeIntervalSince(now) / 60).rounded()) }

    @Test func nowIsWednesday1418() {
        let parts = Calendar.konstanz.dateComponents([.weekday, .hour, .minute, .day, .month], from: now)
        #expect(parts.weekday == 4 && parts.hour == 14 && parts.minute == 18 && parts.day == 28 && parts.month == 10)
    }

    @Test func stopScreenDepartures() throws {
        // Screen 09: 9A Universität (A) 3, 1 Staad (B) 6, 5 Petershausen (A) 11, 9A 18, 1 21.
        let rows = try sample.departures(at: DesignSample.sternenplatz.id, from: now, limit: 5)
        #expect(rows.map(\.line.name) == ["9A", "1", "5", "9A", "1"])
        #expect(rows.map(\.headsign) == ["Universität", "Staad", "Petershausen", "Universität", "Staad"])
        #expect(rows.map(\.platform.code) == ["A", "B", "A", "A", "B"])
        #expect(rows.map { minutes($0.scheduled) } == [3, 6, 11, 18, 21])
        #expect(rows.allSatisfy { $0.status == .scheduled })
    }

    @Test func linesTabTimes() throws {
        // Screen 09 "Linien": 1 → 14:24 · 14:39 · 14:54, 5 → 14:29 · 14:44 · 14:59, 9A → 14:21 · 14:36 · 14:51.
        let groups = try sample.departuresByLine(at: DesignSample.sternenplatz.id, from: now)
        #expect(groups.map(\.line.name) == ["1", "5", "9A"])
        let times = groups.map { $0.departures.map { ServiceClock().runningDays(at: $0.scheduled)[0].minutes } }
        #expect(times == [[864, 879, 894], [869, 884, 899], [861, 876, 891]])
    }

    @Test func favouriteStopsTicking() throws {
        // Screen 12: Bahnhof 5 in 4, 9A in 9.
        let bahnhof = try sample.departures(at: DesignSample.bahnhof.id, from: now, limit: 2)
        #expect(bahnhof.map { "\($0.line.name) \(minutes($0.scheduled))" } == ["5 4", "9A 9"])
    }

    @Test func tripScreen() throws {
        // Screen 17: 7 stops, Sternenplatz 14:35 (Steig D) … Universität 14:52, 17 minutes.
        let trip = try #require(try sample.trip(id: 1, on: DesignSample.day))
        #expect(trip.stops.map(\.station.name) == ["Sternenplatz", "Petershausen Bahnhof", "Jahnstraße",
                                                   "Mainaustraße", "Egg", "Riedstraße", "Universität"])
        #expect(trip.stops.first?.platform.code == "D")
        #expect(minutes(trip.stops[0].departure) == 17)
        #expect(Int(trip.stops[6].arrival.timeIntervalSince(trip.stops[0].departure) / 60) == 17)
    }

    @Test func threeConnections() throws {
        // Screen 10: three options. The change at Bahnhof: bus 14:24 → 14:42 (the card's 18 minutes count from the
        // first bus), plus the 4-minute walk before it.
        let journeys = try sample.plan(PlanRequest(from: Endpoint(name: "Mein Standort", coordinate: DesignSample.sternenplatz.coordinate),
                                                   to: Endpoint(name: "Universität", coordinate: DesignSample.universitaet.coordinate),
                                                   time: now))
        #expect(journeys.count == 3)
        #expect(journeys[1].transfers == 1 && journeys[1].minutes == 22)
        let firstBus = try #require(journeys[1].firstRide)
        #expect(Int(journeys[1].end.timeIntervalSince(firstBus.start) / 60) == 18)
        #expect(journeys[1].rides.map(\.line.name) == ["1", "5"])
        #expect(journeys[2].walkingMinutes == 1)
        #expect(journeys.allSatisfy { $0.legs.count >= 2 })
    }

    @Test func journeyScreenProgress() {
        // Screen 11 at 14:24, between Sternenplatz and Petershausen... at Petershausen: 3 stops left, 11 Min.
        let progress = TripProgress(ride: DesignSample.ride9A, at: DesignSample.at(14, 24))
        #expect(progress.currentStop == 1)
        #expect(progress.stopsLeft == 3)
        #expect(progress.minutesToArrival == 11)
    }

    @Test func searchUni() {
        // Screen 08: Universität (stop, 9A), Universität Konstanz, Universitätsstraße; "Uni" bold.
        let results = sample.search("Uni", near: PlaceSearch.konstanzCentre)
        #expect(results.map(\.name) == ["Universität", "Universität Konstanz", "Universitätsstraße"])
        #expect(results.allSatisfy { $0.match == 0..<3 })
    }

    @Test func walkSteps() {
        // Screen 22: 80 m Fischmarkt, right into Bahnhofstraße 120 m, cross Konzilstraße 15 m, arrive.
        let steps = DesignSample.walkToSternenplatz
        #expect(steps.map(\.metres) == [80, 120, 15, 0])
        #expect(steps.map(\.maneuver) == [.depart, .right, .cross, .arrive])
    }

    @Test func userData() {
        #expect(DesignSample.favorites().compactMap(\.slot) == [.home, .uni])
        #expect(DesignSample.recent().count == 6)
    }

    @Test func realAndSampleShareTheProtocol() throws {
        let services: [any TransitService] = [sample, try OfflineTransit(data: repoData)]
        for service in services {
            #expect(!service.stations.isEmpty)
            #expect(service.timetableInfo != nil)
        }
    }
}
