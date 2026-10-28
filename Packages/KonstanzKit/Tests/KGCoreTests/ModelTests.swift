import Foundation
import Testing
@testable import KGCore

@Suite("Geo")
struct GeoTests {
    let bahnhof = Coordinate(latitude: 47.6585, longitude: 9.1772)
    let uni = Coordinate(latitude: 47.6893, longitude: 9.1871)

    @Test func distanceBahnhofToUniversityIsAbout3_5km() {
        let metres = bahnhof.distance(to: uni)
        #expect(metres > 3_300 && metres < 3_600, "got \(metres)")
    }

    @Test func distanceIsSymmetricAndZeroToItself() {
        #expect(bahnhof.distance(to: bahnhof) == 0)
        #expect(abs(bahnhof.distance(to: uni) - uni.distance(to: bahnhof)) < 0.001)
    }

    @Test func bearingPointsNorthAndEast() {
        let north = Coordinate(latitude: 47.7, longitude: 9.18)
        let east = Coordinate(latitude: 47.66, longitude: 9.25)
        let here = Coordinate(latitude: 47.66, longitude: 9.18)
        #expect(abs(here.bearing(to: north) - 0) < 0.5)
        #expect(abs(here.bearing(to: east) - 90) < 0.5)
    }

    @Test func walkingMinutesRoundUpAndAreAtLeastOne() {
        #expect(Walking.minutes(forMetres: 0) == 1)
        #expect(Walking.minutes(forMetres: 75) == 1)
        #expect(Walking.minutes(forMetres: 76) == 2)
        #expect(Walking.minutes(forMetres: 220) == 3)  // design 22: "3 Min. · 220 m"
    }
}

@Suite("Journey")
struct JourneyTests {
    let line9A = Line(id: 1, name: "9A", longName: "", isCity: true)
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    func stop(_ name: String, minutes: Int) -> TripStop {
        let station = Station(id: name.hashValue, name: name, shortName: name, coordinate: .init(latitude: 47.66, longitude: 9.17))
        let platform = Platform(id: name.hashValue, stationID: station.id, code: "D", coordinate: station.coordinate, direction: nil)
        let time = start.addingTimeInterval(TimeInterval(minutes * 60))
        return TripStop(station: station, platform: platform, arrival: time, departure: time)
    }

    /// Design 21: walk 2 Min. · 9A 10 Min. · walk 2 Min., 14:21–14:35.
    var designJourney: Journey {
        Journey(legs: [
            .walk(WalkLeg(start: start, end: start.addingTimeInterval(120), metres: 150, destinationName: "Sternenplatz")),
            .ride(RideLeg(tripID: 7, line: line9A, headsign: "Universität",
                          stops: [stop("Sternenplatz", minutes: 2), stop("Universität", minutes: 12)])),
            .walk(WalkLeg(start: start.addingTimeInterval(720), end: start.addingTimeInterval(840), metres: 140, destinationName: "Universität")),
        ])
    }

    @Test func sumsUpLikeTheDesign() {
        let journey = designJourney
        #expect(journey.minutes == 14)
        #expect(journey.walkingMinutes == 4)
        #expect(journey.walkingMetres == 290)
        #expect(journey.transfers == 0)
        #expect(journey.firstRide?.line.name == "9A")
        #expect(journey.legs.map(\.minutes) == [2, 10, 2])
    }

    @Test func idDependsOnTheTripsRidden() {
        #expect(designJourney.id == designJourney.id)
        #expect(designJourney.id.contains("r7"))
    }
}

@Suite("Status and user data")
struct StatusAndUserDataTests {
    @Test func onlyLiveCountsAsLive() {
        #expect(DepartureStatus.scheduled.isLive == false)
        #expect(DepartureStatus.live(delayMinutes: 0).isLive)
        #expect(DepartureStatus.live(delayMinutes: 3).delayMinutes == 3)
    }

    @Test func expectedTimeAddsTheDelay() {
        let platform = Platform(id: 1, stationID: 1, code: "A", coordinate: .init(latitude: 0, longitude: 0), direction: nil)
        let line = Line(id: 1, name: "1", longName: "", isCity: true)
        let time = Date(timeIntervalSince1970: 0)
        let late = Departure(tripID: 1, line: line, headsign: "Staad", platform: platform, scheduled: time, status: .live(delayMinutes: 2))
        #expect(late.expected == time.addingTimeInterval(120))
        #expect(Departure(tripID: 1, line: line, headsign: "Staad", platform: platform, scheduled: time).expected == time)
    }

    @Test func alarmFiresBeforeTheDeparture() {
        let departure = Date(timeIntervalSince1970: 10_000)
        let alarm = Alarm(stationID: 1, stationName: "Sternenplatz", tripID: 2, lineName: "9A", headsign: "Universität",
                          platformCode: "D", departure: departure, minutesBefore: 2)
        #expect(alarm.fireDate == departure.addingTimeInterval(-120))
    }

    @Test func savedTargetsSurviveEncoding() throws {
        let favorite = Favorite(slot: .home, target: .point(name: "Seestraße 21", coordinate: .init(latitude: 47.66, longitude: 9.18)), order: 0)
        let decoded = try JSONDecoder().decode(Favorite.self, from: JSONEncoder().encode(favorite))
        #expect(decoded == favorite)
        #expect(decoded.displayName == "Seestraße 21")
    }

    @Test func placeKindsCoverEveryKindInTheData() throws {
        // Every `place.kind` in timetable.db must map to a PlaceKind.
        let kinds = ["Venue", "Station", "Harbour", "Library", "Square", "University", "Street", "District", "Town"]
        for kind in kinds { #expect(PlaceKind(rawValue: kind) != nil, "\(kind)") }
    }
}
