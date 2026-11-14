import Foundation
import KGLiveAPI
import Testing

@Test func snapshotRoundTrips() throws {
    let snapshot = LiveSnapshot(generatedAt: 1_794_560_000, upstream: .ok,
                                trips: [TripLiveDTO(k: "20261110|1|de:08335:6554|553", d: 120, t: 1_794_559_990)],
                                cancelled: ["20261110|9A|de:08335:11925|600"])
    let data = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(LiveSnapshot.self, from: data) == snapshot)
}

@Test func decodingIgnoresUnknownFieldsAndStates() throws {
    let json = Data("""
    {"v":1,"generatedAt":5,"upstream":"maintenance","trips":[{"k":"a","d":3,"t":4,"x":true}],"cancelled":[],"new":1}
    """.utf8)
    let snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: json)
    #expect(snapshot.upstream == .degraded)
    #expect(snapshot.trips == [TripLiveDTO(k: "a", d: 3, t: 4)])
}

@Test func tripKeyUsesTheStopArea() {
    #expect(TripKey.make(serviceDate: 20_261_110, line: "1", firstPlatform: "de:08335:6554:10:1", firstDeparture: 553)
        == "20261110|1|de:08335:6554|553")
    #expect(TripKey.stopGID(of: "de:08335:6554:1") == "de:08335:6554")
    #expect(TripKey.stopGID(of: "ch:23021:20261") == "ch:23021:20261")
}

@Test func stopGIDCheck() {
    #expect(TripKey.isStopGID("de:08335:11918"))
    #expect(!TripKey.isStopGID("de:08335:11918:0:1"))
    #expect(!TripKey.isStopGID("8711918"))
    #expect(!TripKey.isStopGID("de:08335:11918&limit=999"))
}
