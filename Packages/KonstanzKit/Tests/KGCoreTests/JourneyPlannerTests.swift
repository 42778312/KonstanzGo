import Foundation
import Testing
@testable import KGCore

/// Against the real bundled timetable (feed 20261011).
@Suite("Journey planner")
struct JourneyPlannerTests {
    let store: TimetableStore
    let planner: JourneyPlanner
    let clock = ServiceClock()

    init() throws {
        store = try TimetableStore(url: repoData.timetable)
        planner = try JourneyPlanner(store: store, url: repoData.timetable)
    }

    func at(_ yyyymmdd: Int, _ hour: Int, _ minute: Int) -> Date {
        clock.date(ServiceDay(yyyymmdd: yyyymmdd), minutes: hour * 60 + minute)
    }

    func endpoint(station id: Int) throws -> Endpoint {
        let station = try #require(store.station(id: id))
        return Endpoint(name: station.shortName, coordinate: station.coordinate)
    }

    var sternenplatz: Endpoint { get throws { try endpoint(station: 99) } }
    var universitaet: Endpoint { get throws { try endpoint(station: 3) } }
    var bahnhof: Endpoint { get throws { try endpoint(station: 15) } }

    /// Every ride's line follows the streets: line 9 from Universität loops out to Pfeiferhölzle and back, and
    /// used to be drawn as one straight line because the loop is far longer than the way as the crow flies.
    @Test func ridesFollowTheirShape() throws {
        let journeys = try planner.plan(PlanRequest(from: universitaet, to: sternenplatz, time: at(20261028, 22, 0)))
        let rides = journeys.flatMap(\.rides)
        #expect(!rides.isEmpty)
        for ride in rides where ride.stops.count > 2 {
            // A shape piece has many points; the fallback is just the stops.
            #expect(ride.path.count > ride.stops.count + 2,
                    "line \(ride.line.name) from \(ride.boarding.station.shortName): \(ride.path.count) points")
            // It passes every stop.
            for stop in ride.stops {
                let nearest = ride.path.map { $0.distance(to: stop.platform.coordinate) }.min() ?? .infinity
                #expect(nearest < 60, "\(stop.station.shortName) is \(Int(nearest)) m off line \(ride.line.name)")
            }
        }
    }

    /// Just before midnight the next service day's night train is an option, with the right stops and time.
    @Test func justBeforeMidnightTheNextServiceDaysTripsCount() throws {
        let kreuzlingen = try endpoint(station: 108)
        let journeys = try planner.plan(PlanRequest(from: bahnhof, to: kreuzlingen, time: at(20261105, 23, 59)))
        let ride = try #require(journeys.flatMap(\.rides).first { $0.start == at(20261106, 0, 9) })
        #expect(ride.line.name == "S14")
        #expect(ride.stops.last?.station.id == 108)
    }

    /// The next morning's first bus is not a "next bus" late at night: that's screen 23's job.
    @Test func tomorrowsMorningIsNotPlannedTonight() throws {
        let journeys = try planner.plan(PlanRequest(from: sternenplatz, to: universitaet, time: at(20261105, 23, 59)))
        #expect(journeys.flatMap(\.rides).allSatisfy { $0.start < at(20261106, 3, 0) })
    }

    @Test func sternenplatzToUniversityOnAWednesdayAfternoon() throws {
        let leave = at(20261028, 14, 0)
        let journeys = try planner.plan(PlanRequest(from: sternenplatz, to: universitaet, time: leave))
        let bus = journeys.filter { !$0.rides.isEmpty }
        #expect(!bus.isEmpty)
        #expect(bus.count <= JourneyPlanner.maxOptions)
        let best = try #require(journeys.first)
        #expect(best.end < at(20261028, 14, 45), "arrives \(best.end)")
        // Every journey leaves no earlier than asked and its legs are back to back.
        for journey in journeys {
            #expect(journey.start >= leave.addingTimeInterval(-60))
            for (a, b) in zip(journey.legs, journey.legs.dropFirst()) {
                #expect(a.end <= b.start, "legs overlap in \(journey.id)")
            }
            for ride in journey.rides {
                #expect(ride.stops.count >= 2)
                #expect(ride.start >= leave)
                #expect(ride.path.count >= 2)
            }
        }
    }

    @Test func optionsAreDistinctAndNoneIsBeatenByAnother() throws {
        let journeys = try planner.plan(PlanRequest(from: sternenplatz, to: universitaet, time: at(20261028, 14, 0)))
        let bus = journeys.filter { !$0.rides.isEmpty }
        #expect(Set(bus.map { $0.rides.map(\.tripID) }).count == bus.count)
        for a in bus {
            for b in bus where a.id != b.id {
                let beats = b.start >= a.start && b.end <= a.end && (b.start > a.start || b.end < a.end)
                #expect(!beats, "\(b.id) beats \(a.id)")
            }
        }
    }

    @Test func arriveByArrivesInTime() throws {
        let deadline = at(20261028, 15, 0)
        let journeys = try planner.plan(PlanRequest(from: bahnhof, to: universitaet, time: deadline, arriveBy: true))
        #expect(!journeys.filter { !$0.rides.isEmpty }.isEmpty)
        #expect(journeys.allSatisfy { $0.end <= deadline })
        // The first one leaves as late as possible.
        let starts = journeys.map(\.start)
        #expect(journeys.first?.start == starts.max())
    }

    @Test func nightBusToMainauAt0144() throws {
        // The design's "no bus at 01:30" example does not hold here: line 4's "Nachtschwärmer" run of
        // Wednesday's service day leaves Sternenplatz at 25:44 = 01:44 on Thursday, via Mainau.
        let mainau = try endpoint(station: 125)
        let journeys = try planner.plan(PlanRequest(from: sternenplatz, to: mainau, time: at(20261029, 1, 30)))
        let first = try #require(journeys.first { !$0.rides.isEmpty })
        #expect(first.start == at(20261028, 25, 44))
        #expect(first.rides.first?.line.name == "4")
    }

    @Test func noBusToMainauBetweenTheLastNightBusAndMorning() throws {
        // Design 23's case, at a time when really nothing runs: the next bus is the first one at 05:19.
        let mainau = try endpoint(station: 125)
        let journeys = try planner.plan(PlanRequest(from: sternenplatz, to: mainau, time: at(20261029, 2, 10)))
        let bus = journeys.filter { !$0.rides.isEmpty }
        #expect(bus.allSatisfy { $0.start >= at(20261029, 5, 19) })
        #expect(bus.first?.start == at(20261029, 5, 19))
    }

    @Test func shortTripsAlsoOfferWalking() throws {
        // Sternenplatz → Bahnhof is about a kilometre.
        let journeys = try planner.plan(PlanRequest(from: sternenplatz, to: bahnhof, time: at(20261028, 14, 0)))
        let walk = try #require(journeys.first { $0.rides.isEmpty })
        #expect(walk.legs.count == 1)
        #expect(walk.minutes <= 20)
    }

    @Test func preferencesReorder() throws {
        let request = try PlanRequest(from: sternenplatz, to: universitaet, time: at(20261028, 14, 0))
        let journeys = try planner.plan(request)
        let byWalking = JourneyPlanner.ranked(journeys, by: .leastWalking, arriveBy: false)
        #expect(byWalking.map(\.walkingMinutes) == byWalking.map(\.walkingMinutes).sorted())
        let byTransfers = JourneyPlanner.ranked(journeys, by: .fewestTransfers, arriveBy: false)
        #expect(byTransfers.map(\.transfers) == byTransfers.map(\.transfers).sorted())
    }

    @Test func tagsMarkTheFastestAndDifferentAlternatives() throws {
        let journeys = try planner.plan(PlanRequest(from: sternenplatz, to: universitaet, time: at(20261028, 14, 0)))
        let tags = JourneyPlanner.tags(for: journeys)
        #expect(tags.values.filter { $0.contains(.fastest) }.count == 1)
        #expect(tags.values.filter { $0.contains(.leastWalking) }.count <= 1)
        #expect(tags.values.filter { $0.contains(.fewestTransfers) }.count <= 1)
    }

    @Test func nightBusesOfThePreviousDayCanBeUsed() throws {
        // Departing just after midnight still finds the night buses of the day before (or none),
        // but never a journey that starts before the requested time.
        let leave = at(20261031, 0, 10)
        let journeys = try planner.plan(PlanRequest(from: bahnhof, to: sternenplatz, time: leave))
        #expect(journeys.allSatisfy { $0.start >= leave.addingTimeInterval(-60) })
    }

    @Test func withTheWalkingRouterWalksFollowTheStreets() throws {
        let walker = WalkRouter(graph: try WalkGraph.read(from: repoData.walkGraph))
        let streets = try JourneyPlanner(store: store, url: repoData.timetable, walker: walker)
        let request = try PlanRequest(from: sternenplatz, to: bahnhof, time: at(20261028, 14, 0))
        let walk = try #require(try streets.plan(request).first { $0.rides.isEmpty }?.walks.first)
        #expect(walk.path.count > 2)
        #expect(walk.steps.first?.maneuver == .depart && walk.steps.last?.maneuver == .arrive)
        // Same options and times as without it: only the walks' shapes and steps change.
        let plain = try planner.plan(request)
        let withStreets = try streets.plan(request)
        #expect(plain.filter { !$0.rides.isEmpty }.map(\.id) == withStreets.filter { !$0.rides.isEmpty }.map(\.id))
        #expect(plain.filter { !$0.rides.isEmpty }.map(\.end) == withStreets.filter { !$0.rides.isEmpty }.map(\.end))
    }

    @Test func accessIncludesTheNearestTwoEvenFarAway() {
        // A point on the lake, far from any stop.
        let access = planner.access(near: Coordinate(latitude: 47.62, longitude: 9.30))
        #expect(access.count == 2)
        #expect(access.allSatisfy { $0.walkMinutes > 15 })
    }

    @Test func planningIsFast() throws {
        let pairs = [(99, 3), (15, 125), (3, 15), (99, 15), (125, 3)]
        _ = try planner.plan(PlanRequest(from: sternenplatz, to: universitaet, time: at(20261028, 8, 0)))  // warm up
        let start = Date()
        for (a, b) in pairs {
            for hour in [7, 12, 17] {
                _ = try planner.plan(PlanRequest(from: endpoint(station: a), to: endpoint(station: b),
                                                 time: at(20261028, hour, 0)))
            }
        }
        let perPlan = Date().timeIntervalSince(start) / Double(pairs.count * 3)
        // Plan C4: < 150 ms on an iPhone 12. A Mac is a few times faster, so allow 50 ms here.
        #expect(perPlan < 0.05, "\(Int(perPlan * 1000)) ms per plan")
    }

    @Test func buildingADaysNetworkIsQuick() throws {
        let start = Date()
        _ = try planner.scan(for: ServiceDay(yyyymmdd: 20261105))
        #expect(Date().timeIntervalSince(start) < 0.5)
    }
}
