import KGCore
import Testing
@testable import KGFeatures

@Suite("Opening saved things on the map")
struct MapSheetTests {
    let stop = SavedTarget.station(id: 15, name: "Bahnhof", coordinate: Coordinate(latitude: 47.66, longitude: 9.18))

    @Test("a saved stop opens with its departures")
    func savedStop() {
        #expect(MapSheet.opening(stop) { $0 == 15 } == .station(15))
    }

    @Test("a saved stop that left the timetable opens as a place")
    func retiredStop() {
        #expect(MapSheet.opening(stop) { _ in false } == .place(stop))
    }

    @Test("a saved place opens as a place")
    func savedPlace() {
        let pin = SavedTarget.point(name: "Pin", coordinate: Coordinate(latitude: 47.66, longitude: 9.18))
        #expect(MapSheet.opening(pin) { _ in true } == .place(pin))
    }
}
