import Foundation
import Testing
@testable import KGCore

@Suite("Shapes")
struct ShapeTests {
    // A street going east and back west 30 m further north (an out-and-back loop).
    let out = (0...10).map { Coordinate(latitude: 47.66, longitude: 9.17 + Double($0) * 0.0005) }
    var back: [Coordinate] { out.reversed().map { Coordinate(latitude: $0.latitude + 0.0003, longitude: $0.longitude) } }

    @Test func densifyAddsPointsOnLongStretches() {
        let line = [Coordinate(latitude: 47.66, longitude: 9.17), Coordinate(latitude: 47.66, longitude: 9.18)]
        let dense = Shapes.densify(line)
        #expect(dense.count > 50)
        #expect(zip(dense, dense.dropFirst()).allSatisfy { $0.0.distance(to: $0.1) <= Shapes.step + 0.01 })
    }

    @Test func takesTheFirstPassOnAnOutAndBackLine() {
        // Stops: start of the way out, the far end, then the start again on the way back.
        let shape = Shapes.densify(out + back)
        let stops = [out[0], out[10], back[10]]
        let matched = Shapes.match(stops, to: shape)
        #expect(matched?.count == 3)
        // The first stop is matched at the start, not on the way back past the same place.
        #expect((matched?[0] ?? 999) < shape.count / 4)
        #expect(matched == matched?.sorted())
    }

    @Test func aDetourWithNoShortWayIsRefused() {
        // From A 2 km north and back down to B, 375 m east of A: the bus doesn't drive that in a minute.
        let a = out[0], b = out[10]
        let far = Coordinate(latitude: 47.68, longitude: 9.17)
        let shape = Shapes.densify([a, far, b])
        #expect(Shapes.piece(of: shape, from: 0, to: shape.count - 1, between: a, and: b, seconds: 60,
                             topSpeed: 22) == nil)
    }

    @Test func aBranchBackPastTheStopTakesTheShortWay() {
        // The shape runs from A out a 1 km branch, back past A, then on to B: the bus goes straight on.
        let a = out[0], b = out[4]
        let branch = Coordinate(latitude: 47.669, longitude: 9.17)
        let shape = Shapes.densify([a, branch, a, b])
        let to = shape.count - 1
        let piece = Shapes.piece(of: shape, from: 0, to: to, between: a, and: b)
        let length = piece.map { zip($0, $0.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }
        #expect(length.map { $0 < 300 } == true, "piece length \(String(describing: length))")
    }
}

@Suite("Trajectory")
struct TrajectoryTests {
    let line = Line(id: 1, name: "9", longName: "", isCity: true)
    let stops = [Coordinate(latitude: 47.66, longitude: 9.17), Coordinate(latitude: 47.666, longitude: 9.17),
                 Coordinate(latitude: 47.672, longitude: 9.17)]

    func trajectory(_ times: [(Int, Int)]) throws -> Trajectory {
        try #require(Trajectory(tripID: 1, line: line, headsign: "Universität",
                                calls: zip(stops, times).map { TimedStop(coordinate: $0, arrival: $1.0, departure: $1.1) },
                                shape: []))
    }

    @Test func sCurveStartsAndEndsSlowly() {
        #expect(Trajectory.travelled(0, duration: 120) == 0)
        #expect(Trajectory.travelled(120, duration: 120) == 1)
        #expect(abs(Trajectory.travelled(60, duration: 120) - 0.5) < 1e-9)
        // Slower than linear while speeding up, faster than linear before braking.
        #expect(Trajectory.travelled(6, duration: 120) < 6.0 / 120)
        #expect(Trajectory.travelled(114, duration: 120) > 114.0 / 120)
        // Monotonic.
        let samples = stride(from: 0.0, through: 120, by: 1).map { Trajectory.travelled($0, duration: 120) }
        #expect(samples == samples.sorted())
    }

    @Test func notOnTheMapBeforeTheFirstOrAfterTheLastStop() throws {
        let trip = try trajectory([(600, 600), (602, 602), (604, 604)])
        #expect(trip.position(at: 600 * 60 - 1) == nil)
        #expect(trip.position(at: 604 * 60 + 1) == nil)
        #expect(trip.position(at: 600 * 60) != nil)
    }

    @Test func movesForwardAndHeadsNorth() throws {
        let trip = try trajectory([(600, 600), (602, 602), (604, 604)])
        var last = -1.0
        for second in stride(from: 600.0 * 60, through: 604 * 60, by: 5) {
            let position = try #require(trip.position(at: second))
            #expect(position.coordinate.latitude >= last - 1e-9)
            last = position.coordinate.latitude
            #expect(position.isEstimated)
        }
        let middle = try #require(trip.position(at: 601 * 60))
        #expect(middle.heading < 1 || middle.heading > 359)
    }

    @Test func waitsAtAStopWithoutATimetabledWait() throws {
        // Arrival = departure at the middle stop: it gets a short dwell before leaving at 602:00.
        let trip = try trajectory([(600, 600), (602, 602), (604, 604)])
        let justBefore = try #require(trip.position(at: 602 * 60 - 5))
        #expect(justBefore.coordinate.distance(to: stops[1]) < 1)
    }

    @Test func stopsSharingAMinuteAreSpreadOut() {
        var arrival = [0.0, 60, 60, 120], departure = [0.0, 60, 60, 120]
        Trajectory.smoothTimes(arrival: &arrival, departure: &departure, distance: [0, 500, 1_000, 1_500], topSpeed: 22)
        #expect(arrival == arrival.sorted())
        #expect(arrival[2] > arrival[1])
    }
}

/// Against the real timetable.
@Suite("Vehicle tracker")
struct VehicleTrackerTests {
    let store: TimetableStore
    let tracker: VehicleTracker
    let clock = ServiceClock()

    init() throws {
        store = try TimetableStore(url: repoData.timetable)
        tracker = try VehicleTracker(store: store, url: repoData.timetable)
    }

    func at(_ yyyymmdd: Int, _ hour: Int, _ minute: Int, second: Int = 0) -> Date {
        clock.date(ServiceDay(yyyymmdd: yyyymmdd), minutes: hour * 60 + minute).addingTimeInterval(TimeInterval(second))
    }

    @Test func manyBusesOnAWednesdayAfternoon() throws {
        let buses = try tracker.positions(at: at(20261028, 14, 0), cityOnly: true)
        #expect(buses.count > 15 && buses.count < 200, "\(buses.count) buses")
        #expect(Set(buses.map(\.tripID)).count == buses.count)
        // All in and around Konstanz.
        #expect(buses.allSatisfy { (47.6...47.75).contains($0.coordinate.latitude) })
    }

    /// The map agrees with the departure lists: no bus leaves before its time, or long after it.
    @Test func busesLeaveStopsWhenTheListSays() throws {
        let day = ServiceDay(yyyymmdd: 20261028)
        for trip in try tracker.trips(on: day) {
            guard let line = store.line(id: trip.route), line.isCity,
                  let trajectory = try tracker.trajectory(trip, line: line, day: day) else { continue }
            for (index, call) in trip.calls.enumerated() {
                let late = trajectory.departure[index] - Double(call.departure) * 60
                #expect(late >= 0 && late <= Trajectory.sharedMinuteSeconds, "trip \(trip.trip) stop \(index): \(late) s")
            }
        }
    }

    @Test func aBusIsAtItsStopWhenItDeparts() throws {
        let departure = try #require(try store.departures(at: 99, from: at(20261028, 14, 0)).first { $0.line.name == "9A" })
        let position = try #require(try tracker.position(ofTrip: departure.tripID, on: ServiceDay(yyyymmdd: 20261028),
                                                          at: departure.scheduled.addingTimeInterval(-3)))
        #expect(position.coordinate.distance(to: departure.platform.coordinate) < 30,
                "\(Int(position.coordinate.distance(to: departure.platform.coordinate))) m from the platform")
    }

    @Test func nightBusOfTheDayBeforeIsOnTheRoadAfterMidnight() throws {
        // Line 4's night run leaves Sternenplatz at 25:44 on Wednesday's service day = 01:44 on Thursday.
        let night = try tracker.positions(at: at(20261029, 1, 45))
        #expect(night.contains { $0.line.name == "4" })
    }

    @Test func positionsAreQuickOnceLoaded() throws {
        _ = try tracker.positions(at: at(20261028, 14, 0))
        let start = Date()
        for second in 0..<10 { _ = try tracker.positions(at: at(20261028, 14, 0, second: second)) }
        let perFrame = Date().timeIntervalSince(start) / 10
        #if DEBUG
        let budget = 0.1
        #else
        let budget = 0.016
        #endif
        #expect(perFrame < budget, "\(Int(perFrame * 1000)) ms per update")
    }
}

@Suite("Trip progress")
struct TripProgressTests {
    let line = Line(id: 1, name: "9A", longName: "", isCity: true)
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    /// Design 11: Sternenplatz 14:21, Petershausen, Jahnstraße 14:27, Egg 14:31, Universität 14:35.
    var ride: RideLeg {
        let names = ["Sternenplatz", "Petershausen", "Jahnstraße", "Egg", "Universität"]
        let minutes = [0, 3, 6, 10, 14]
        let stops = zip(names, minutes).enumerated().map { index, pair in
            let coordinate = Coordinate(latitude: 47.66 + Double(index) * 0.005, longitude: 9.17)
            let station = Station(id: index, name: pair.0, shortName: pair.0, coordinate: coordinate)
            let platform = Platform(id: index, stationID: index, code: nil, coordinate: coordinate, direction: nil)
            let time = start.addingTimeInterval(TimeInterval(pair.1 * 60))
            return TripStop(station: station, platform: platform, arrival: time, departure: time)
        }
        return RideLeg(tripID: 1, line: line, headsign: "Universität", stops: stops)
    }

    @Test func beforeBoarding() {
        let progress = TripProgress(ride: ride, at: start.addingTimeInterval(-120))
        #expect(progress.phase == .waiting)
        #expect(progress.stopsLeft == 4)
        #expect(progress.minutesToArrival == 16)
        #expect(progress.fraction == 0)
    }

    @Test func betweenTheFirstStops() {
        // Design: "Noch 4 Haltestellen!", "11 Min.", between Sternenplatz and Petershausen.
        let progress = TripProgress(ride: ride, at: start.addingTimeInterval(170))
        #expect(progress.phase == .driving)
        #expect(progress.currentStop == 0)
        #expect(progress.stopsLeft == 4)
        #expect(progress.minutesToArrival == 12)
    }

    @Test func atAStopOnTheWay() {
        let progress = TripProgress(ride: ride, at: start.addingTimeInterval(360))
        #expect(progress.phase == .atStop)
        #expect(progress.currentStop == 2)
        #expect(progress.stopsLeft == 2)
        #expect(abs(progress.fraction - 6.0 / 14) < 1e-9)
    }

    @Test func arrived() {
        let progress = TripProgress(ride: ride, at: start.addingTimeInterval(14 * 60 + 5))
        #expect(progress.phase == .arrived)
        #expect(progress.stopsLeft == 0)
        #expect(progress.minutesToArrival == 0)
        #expect(progress.fraction == 1)
    }

    @Test func positionWinsWhenTheBusIsLate() {
        // By the clock it should be at Egg, but the phone is still at Petershausen.
        let late = TripProgress(ride: ride, at: start.addingTimeInterval(600),
                                near: Coordinate(latitude: 47.665, longitude: 9.17))
        #expect(late.currentStop == 1)
        #expect(late.stopsLeft == 3)
        // Far from every stop: the timetable stays.
        let away = TripProgress(ride: ride, at: start.addingTimeInterval(600), near: Coordinate(latitude: 47.0, longitude: 9.0))
        #expect(away.currentStop == 3)
    }
}

/// The main map's moving buses and trains, from the real bundled timetable.
@Suite("Map vehicles")
struct MapVehicleTests {
    let store: TimetableStore
    let tracker: VehicleTracker
    let clock = ServiceClock()

    init() throws {
        store = try TimetableStore(url: repoData.timetable)
        tracker = try VehicleTracker(store: store, url: repoData.timetable)
    }

    private func line(_ name: String, mode: VehicleMode = .bus) throws -> Line {
        try #require(store.lines.first { $0.name == name && $0.mode == mode })
    }

    @Test func kreuzlingenBuses700And203AreYellow() throws {
        for name in ["908", "925", "EV1", "700", "203", "203S"] { #expect(try line(name).isYellowBus, "\(name)") }
        for name in ["5", "9", "13/4", "204", "7394"] { #expect(try !line(name).isYellowBus, "\(name)") }
        #expect(try !line("S14", mode: .train).isYellowBus)
    }

    @Test func busesAndTrainsRunOnAWeekdayAfternoon() throws {
        let now = clock.date(ServiceDay(yyyymmdd: 20261028), minutes: 16 * 60 + 30)
        let started = ContinuousClock.now
        let vehicles = try tracker.positions(at: now)
        #expect(vehicles.contains { $0.line.mode == .bus && $0.line.isCity })
        #expect(vehicles.contains { $0.line.mode == .train })
        #expect(vehicles.contains { $0.line.isYellowBus }, "no yellow bus")
        // The map asks four times a second; once the day is read, an update must be quick.
        let again = ContinuousClock.now
        _ = try tracker.positions(at: now.addingTimeInterval(0.25))
        #expect(ContinuousClock.now - again < .milliseconds(60), "first \(again - started)")
    }
}

/// Every bus and train of a weekday follows its route: along the line's shape, or the streets where the shape
/// has a gap, never a straight line across the Rhine or the lake (line 2's whole route was once drawn as one).
@Suite("Vehicles on their routes")
struct VehicleRouteTests {
    @Test func noStraightCutsOnAWeekday() throws {
        let transit = try OfflineTransit(data: repoData)
        let tracker = transit.tracker
        let day = ServiceDay(yyyymmdd: 20261028)
        var cuts: [String: Int] = [:]
        var legs = 0
        for trip in try tracker.trips(on: day) {
            guard let line = transit.store.line(id: trip.route),
                  let trajectory = try tracker.trajectory(trip, line: line, day: day) else { continue }
            for index in 1..<trip.calls.count {
                legs += 1
                let from = trajectory.callDistance[index - 1], to = trajectory.callDistance[index]
                let between = trajectory.cumulative.filter { $0 > from + 0.5 && $0 < to - 0.5 }.count
                if between == 0, to - from > 150 { cuts["\(line.name) \(line.mode)", default: 0] += 1 }
            }
        }
        #expect(legs > 8_000)
        let buses = cuts.filter { $0.key.hasSuffix("bus") }
        #expect(buses.isEmpty, "straight cuts: \(cuts.sorted { $0.key < $1.key })")
        // Line 2 is a loop; its whole route used to vanish.
        #expect(cuts.keys.allSatisfy { !$0.hasPrefix("2 ") })
    }
}

@Suite("Delay glide")
struct DelayGlideTests {
    @Test func aBusEasesIntoASmallDelayWithoutGoingBackwards() {
        var glide = DelayGlide()
        #expect(glide.advance([1: 30], after: 1) == [1: 0.85])
        // Its timetable clock runs 1 s per second, the delay grows by less: it still creeps forward.
        #expect(DelayGlide.growing < 1)
    }

    @Test func aBusCatchesUpAndABigChangeMovesItAtOnce() {
        var glide = DelayGlide()
        #expect(glide.advance([1: 120], after: 1) == [1: 120])
        #expect(glide.advance([1: 100], after: 1) == [1: 118])
        #expect(glide.advance([:], after: 0.125)[1] == nil)
    }
}
