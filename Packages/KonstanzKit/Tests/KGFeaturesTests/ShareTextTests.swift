import Foundation
import KGCore
import KGDesign
import Testing
@testable import KGFeatures

struct ShareTextTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func stop(_ name: String, id: Int) -> TripStop {
        let spot = Coordinate(latitude: 47.66, longitude: 9.17)
        return TripStop(station: Station(id: id, name: name, shortName: name, coordinate: spot),
                        platform: Platform(id: id, stationID: id, code: "1", coordinate: spot, direction: nil), arrival: start, departure: start)
    }

    private func walk() -> Leg {
        .walk(WalkLeg(start: start, end: start.addingTimeInterval(600), metres: 700, destinationName: "Uni"))
    }

    @Test func namesTheArrivalAndEveryBus() {
        let line = Line(id: 1, name: "9A", longName: "", isCity: true)
        let ride = Leg.ride(RideLeg(tripID: 1, line: line, headsign: "Uni", stops: [stop("A", id: 1), stop("B", id: 2)]))
        let arrival = start.addingTimeInterval(1200)
        let text = JourneyScreen.shareText(Journey(legs: [ride]), arrival: arrival)
        #expect(text.contains(KGStrings.clock(arrival)))
        #expect(text.contains("9A"))
    }

    @Test func aWalkNamesNoBus() {
        let text = JourneyScreen.shareText(Journey(legs: [walk()]), arrival: start)
        #expect(text.contains(KGStrings.clock(start)))
        #expect(!text.contains("Bus") && !text.contains("bus"))
    }
}
