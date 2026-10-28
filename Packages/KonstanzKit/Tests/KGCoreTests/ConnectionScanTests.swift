import Testing
@testable import KGCore

/// Small hand-made networks, so every rule of the scan is checked on its own.
@Suite("Connection scan")
struct ConnectionScanTests {
    // Stations: 1 A, 2 B, 3 C, 4 D (a short walk from C).
    func scan(_ connections: [Connection], footpaths: [Int: [Access]] = [:]) -> ConnectionScan {
        ConnectionScan(connections: connections, footpaths: footpaths)
    }

    @Test func directRide() throws {
        let router = scan([Connection(trip: 10, from: 1, to: 2, departure: 600, arrival: 610)])
        let result = try #require(router.route(origins: [Access(station: 1, walkMinutes: 2)],
                                               destinations: [Access(station: 2, walkMinutes: 3)], departAt: 590))
        #expect(result.arrival == 613)
        #expect(result.leaveAt == 598)
        #expect(result.trips == [10])
    }

    @Test func missesABusThatLeavesBeforeYouGetThere() {
        let router = scan([Connection(trip: 10, from: 1, to: 2, departure: 600, arrival: 610)])
        // Leaving at 599 with a 2-minute walk: at the stop at 601, the bus is gone.
        #expect(router.route(origins: [Access(station: 1, walkMinutes: 2)],
                             destinations: [Access(station: 2, walkMinutes: 0)], departAt: 599) == nil)
    }

    @Test func stayingOnTheSameBusNeedsNoChangeTime() throws {
        let router = scan([
            Connection(trip: 10, from: 1, to: 2, departure: 600, arrival: 605),
            Connection(trip: 10, from: 2, to: 3, departure: 605, arrival: 610),
        ])
        let result = try #require(router.route(origins: [Access(station: 1, walkMinutes: 0)],
                                               destinations: [Access(station: 3, walkMinutes: 0)], departAt: 600))
        #expect(result.arrival == 610)
        #expect(result.parts.count == 1)
    }

    @Test func changingBusesNeedsOneMinute() throws {
        let router = scan([
            Connection(trip: 10, from: 1, to: 2, departure: 600, arrival: 605),
            Connection(trip: 20, from: 2, to: 3, departure: 605, arrival: 608),  // too tight
            Connection(trip: 30, from: 2, to: 3, departure: 606, arrival: 612),
        ])
        let result = try #require(router.route(origins: [Access(station: 1, walkMinutes: 0)],
                                               destinations: [Access(station: 3, walkMinutes: 0)], departAt: 600))
        #expect(result.trips == [10, 30])
        #expect(result.arrival == 612)
    }

    @Test func walksBetweenNearbyStationsToChange() throws {
        let router = scan([
            Connection(trip: 10, from: 1, to: 3, departure: 600, arrival: 610),
            Connection(trip: 20, from: 4, to: 2, departure: 614, arrival: 620),
        ], footpaths: [3: [Access(station: 4, walkMinutes: 3)]])
        let result = try #require(router.route(origins: [Access(station: 1, walkMinutes: 0)],
                                               destinations: [Access(station: 2, walkMinutes: 0)], departAt: 600))
        #expect(result.parts == [
            .ride(trip: 10, from: 1, to: 3, departure: 600, arrival: 610),
            .transfer(from: 3, to: 4, minutes: 3),
            .ride(trip: 20, from: 4, to: 2, departure: 614, arrival: 620),
        ])
    }

    @Test func picksTheExitThatIsQuickestOnFoot() throws {
        // Getting off at B is earlier but the walk from C is much shorter.
        let router = scan([
            Connection(trip: 10, from: 1, to: 2, departure: 600, arrival: 605),
            Connection(trip: 10, from: 2, to: 3, departure: 605, arrival: 608),
        ])
        let result = try #require(router.route(
            origins: [Access(station: 1, walkMinutes: 0)],
            destinations: [Access(station: 2, walkMinutes: 10), Access(station: 3, walkMinutes: 1)], departAt: 600))
        #expect(result.egress.station == 3)
        #expect(result.arrival == 609)
    }

    @Test func walkingOnlyIsNotARoute() {
        let router = scan([], footpaths: [1: [Access(station: 2, walkMinutes: 4)]])
        #expect(router.route(origins: [Access(station: 1, walkMinutes: 0)],
                             destinations: [Access(station: 2, walkMinutes: 0)], departAt: 600) == nil)
    }

    @Test func connectionsAreSortedEvenIfGivenOutOfOrder() throws {
        let router = scan([
            Connection(trip: 20, from: 2, to: 3, departure: 620, arrival: 630),
            Connection(trip: 10, from: 1, to: 2, departure: 600, arrival: 610),
        ])
        let result = try #require(router.route(origins: [Access(station: 1, walkMinutes: 0)],
                                               destinations: [Access(station: 3, walkMinutes: 0)], departAt: 590))
        #expect(result.trips == [10, 20])
    }
}
