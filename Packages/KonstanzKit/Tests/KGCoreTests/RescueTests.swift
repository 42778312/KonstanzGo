import Foundation
import Testing
@testable import KGCore

/// A late bus and a missed change, against the real bundled timetable.
@Suite("Missed connections")
struct RescueTests {
    let store: TimetableStore
    let planner: JourneyPlanner
    let clock = ServiceClock()

    init() throws {
        store = try TimetableStore(url: repoData.timetable)
        planner = try JourneyPlanner(store: store, url: repoData.timetable)
    }

    func at(_ hour: Int, _ minute: Int) -> Date {
        clock.date(ServiceDay(yyyymmdd: 20261105), minutes: hour * 60 + minute)
    }

    /// A real journey with a change in Konstanz at midday.
    func journeyWithChange() throws -> Journey {
        let from = try #require(store.stations.first { $0.shortName == "Sternenplatz" })
        for to in store.stations where to.id != from.id {
            let request = PlanRequest(from: Endpoint(name: from.shortName, coordinate: from.coordinate),
                                      to: Endpoint(name: to.shortName, coordinate: to.coordinate), time: at(12, 0))
            if let journey = try planner.plan(request).first(where: { $0.rides.count == 2 }) { return journey }
        }
        Issue.record("no journey with a change")
        return Journey(legs: [])
    }

    func margin(_ journey: Journey) -> Double {
        journey.rides[1].start.timeIntervalSince(journey.rides[0].end)
    }

    func walkingBetween(_ journey: Journey) -> Double {
        journey.walks.filter { $0.start >= journey.rides[0].end && $0.end <= journey.rides[1].start }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    // MARK: Spotting it

    @Test("on time, the journey is fine")
    func fine() throws {
        let journey = try journeyWithChange()
        #expect(journey.risk(at: journey.start, live: LiveState()) == .fine)
    }

    @Test("the first bus late past the change means the second is missed")
    func missedChange() throws {
        let journey = try journeyWithChange()
        let late = margin(journey) - walkingBetween(journey) + 120
        let live = LiveState(delays: [journey.rides[0].tripID: late])
        guard case let .missed(next, short) = journey.risk(at: journey.start, live: live) else {
            Issue.record("not missed")
            return
        }
        #expect(next.tripID == journey.rides[1].tripID)
        #expect(short == 120)
    }

    @Test("when the next bus is late too, the change still works")
    func nextBusAlsoLate() throws {
        let journey = try journeyWithChange()
        let late = margin(journey) - walkingBetween(journey) + 120
        let live = LiveState(delays: [journey.rides[0].tripID: late, journey.rides[1].tripID: late])
        #expect(!journey.risk(at: journey.start, live: live).isBroken)
    }

    @Test("a change with seconds left is tight, not broken")
    func tight() throws {
        let journey = try journeyWithChange()
        let late = margin(journey) - walkingBetween(journey) - 30
        guard late >= 0 else { return }
        let live = LiveState(delays: [journey.rides[0].tripID: late])
        guard case let .tight(next, seconds) = journey.risk(at: journey.start, live: live) else {
            Issue.record("not tight")
            return
        }
        #expect(next.tripID == journey.rides[1].tripID && seconds == 30)
    }

    @Test("a cancelled bus breaks the journey; one already ridden doesn't")
    func cancelled() throws {
        let journey = try journeyWithChange()
        let live = LiveState(cancelled: [journey.rides[1].tripID])
        #expect(journey.risk(at: journey.start, live: live) == .cancelled(journey.rides[1]))
        let first = LiveState(cancelled: [journey.rides[0].tripID])
        #expect(journey.risk(at: journey.rides[0].end.addingTimeInterval(1), live: first) == .fine)
    }

    @Test("too far from the stop to walk there in time")
    func tooFarToWalk() throws {
        let journey = try journeyWithChange()
        let ride = journey.rides[0]
        let stop = ride.boarding.platform.coordinate
        let far = store.stations.max { $0.coordinate.distance(to: stop) < $1.coordinate.distance(to: stop) }
        let now = ride.start.addingTimeInterval(-60)
        guard case .missed = journey.risk(at: now, live: LiveState(), location: far?.coordinate) else {
            Issue.record("not missed")
            return
        }
        #expect(journey.risk(at: now, live: LiveState(), location: ride.boarding.platform.coordinate) == .fine)
    }

    // MARK: Finding another way

    @Test("on the bus: another way without the missed bus, leaving from a stop still ahead")
    func rescueOnTheBus() throws {
        let journey = try journeyWithChange()
        let first = journey.rides[0], next = journey.rides[1]
        let late = margin(journey) - walkingBetween(journey) + 120
        let live = LiveState(delays: [first.tripID: late])
        let now = first.start.addingTimeInterval(late + 30)
        let options = try planner.rescue(journey, at: now, live: live)
        #expect(!options.isEmpty)
        #expect(options.count <= 3)
        #expect(options.map(\.arrival) == options.map(\.arrival).sorted())
        for option in options {
            #expect(!option.journey.rides.contains { $0.tripID == next.tripID }, "still counts on the missed bus")
            #expect(!option.journey.risk(at: now, live: live).isBroken)
            let target = try #require(journey.target).coordinate
            let end = try #require(option.journey.target).coordinate
            #expect(end.distance(to: target) < 50, "another destination")
            // Rides stay in order, with the delay.
            var ready = now
            for ride in option.journey.rides.dropFirst() {
                #expect(ride.start >= ready.addingTimeInterval(-60))
                ready = ride.end
            }
            if case let .ride(head) = option.journey.legs[0], let stop = option.getOffAt {
                #expect(head.tripID == first.tripID)
                #expect(head.alighting.station.id == stop.id)
            }
        }
    }

    @Test("not on a bus: from where the user stands, right now")
    func rescueFromHere() throws {
        let journey = try journeyWithChange()
        let live = LiveState(cancelled: [journey.rides[0].tripID])
        let here = journey.rides[0].boarding.station.coordinate
        let now = journey.start
        let options = try planner.rescue(journey, at: now, live: live, location: here)
        #expect(!options.isEmpty)
        for option in options {
            #expect(option.getOffAt == nil)
            #expect(!option.journey.rides.contains { $0.tripID == journey.rides[0].tripID })
            #expect(option.journey.start >= now.addingTimeInterval(-60))
        }
    }

    @Test("one click answers at once, also offline")
    func isQuick() throws {
        let journey = try journeyWithChange()
        let start = ContinuousClock.now
        _ = try planner.rescue(journey, at: journey.rides[0].start.addingTimeInterval(30), live: LiveState())
        #expect(ContinuousClock.now - start < .seconds(1))
    }
}
