import Foundation
import Testing
@testable import KGCore

/// Against the real bundled walking network.
@Suite("Walking router")
struct WalkRouterTests {
    static let graph: WalkGraph? = try? WalkGraph.read(from: repoData.walkGraph)
    let router: WalkRouter
    let store: TimetableStore

    init() throws {
        router = WalkRouter(graph: try #require(Self.graph))
        store = try TimetableStore(url: repoData.timetable)
    }

    func station(_ id: Int) throws -> Coordinate { try #require(store.station(id: id)).coordinate }

    @Test func readsTheWholeNetwork() throws {
        let graph = try #require(Self.graph)
        // The numbers DataPipeline/build.sh printed.
        #expect(graph.vertexCount == 29_277)
        #expect(graph.edgeCount == 37_861)
        #expect(graph.nameCount == 1_564)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: WalkGraph.ReadError.self) { try WalkGraph(data: Data("nope".utf8)) }
        #expect(throws: WalkGraph.ReadError.self) { try WalkGraph(data: Data("KWG1".utf8)) }
    }

    @Test func sternenplatzToBahnhof() throws {
        let from = try station(99), to = try station(15)
        let route = try #require(router.route(from: from, to: to))
        let straight = from.distance(to: to)
        #expect(route.metres > straight && route.metres < straight * 1.8, "\(Int(route.metres)) m vs \(Int(straight)) m")
        #expect(route.path.first == from && route.path.last == to)
        #expect(route.steps.first?.maneuver == .depart)
        #expect(route.steps.last?.maneuver == .arrive)
        #expect(route.steps.count >= 3)
        // The steps add up to the walk, give or take their rounding.
        let total = route.steps.reduce(0) { $0 + $1.metres }
        #expect(abs(Double(total) - route.metres) < Double(route.steps.count) * 10 + 30)
        // Named streets show up.
        #expect(route.steps.contains { $0.street != nil })
    }

    @Test func noJumpsInThePath() throws {
        let route = try #require(router.route(from: try station(99), to: try station(3)))
        for (a, b) in zip(route.path, route.path.dropFirst().dropLast()) where a != route.path[0] {
            #expect(a.distance(to: b) < 400, "gap of \(Int(a.distance(to: b))) m")
        }
    }

    @Test func walkAlongOneStreetSegmentStaysOnIt() throws {
        // Two points a quarter and three quarters along one street segment. Here a sidewalk is mapped 1.5 m
        // beside the street and the second point snaps to it; with only the nearest way the walk was a
        // 370 m loop. With nearby ways as candidates it is just that stretch.
        let graph = try #require(Self.graph)
        let edge = try #require(router.snap(try station(99))).edge
        let shape = graph.points(edge)
        func along(_ fraction: Double) -> Coordinate {
            let first = shape[0], last = shape[shape.count - 1]
            return Coordinate(latitude: first.latitude + (last.latitude - first.latitude) * fraction,
                              longitude: first.longitude + (last.longitude - first.longitude) * fraction)
        }
        let from = along(0.25), to = along(0.75)
        let route = try #require(router.route(from: from, to: to))
        #expect(route.metres < from.distance(to: to) * 1.5 + 5, "\(Int(route.metres)) m")
    }

    @Test func realGapsInTheMapStillMeanADetour() throws {
        // At Sternenplatz a point 33 m north lies on a footpath more than 8 m from any other way, joined to the
        // streets only further on. That gap is in the map, so the walk goes round it; it stays bounded.
        let from = try station(99)
        let near = Coordinate(latitude: from.latitude + 0.0003, longitude: from.longitude)
        let route = try #require(router.route(from: from, to: near))
        #expect(route.metres > from.distance(to: near))
        #expect(route.metres < 400)
    }

    @Test func nearbyWaysAreCandidates() throws {
        let candidates = router.candidates(near: try station(99))
        #expect(!candidates.isEmpty && candidates.count <= 4)
        #expect(candidates.map(\.distance) == candidates.map(\.distance).sorted())
    }

    @Test func nothingFarOutsideTheMap() throws {
        let zurich = Coordinate(latitude: 47.3769, longitude: 8.5417)
        #expect(router.route(from: try station(99), to: zurich) == nil)
    }

    @Test func turnsBecomeManeuvers() {
        #expect(WalkDirections.maneuver(forTurn: 0) == .straight)
        #expect(WalkDirections.maneuver(forTurn: 40) == .slightRight)
        #expect(WalkDirections.maneuver(forTurn: 90) == .right)
        #expect(WalkDirections.maneuver(forTurn: 150) == .sharpRight)
        #expect(WalkDirections.maneuver(forTurn: -90) == .left)
        #expect(WalkDirections.maneuver(forTurn: -40) == .slightLeft)
        #expect(WalkDirections.maneuver(forTurn: -150) == .sharpLeft)
        #expect(WalkDirections.maneuver(forTurn: 179) == .uTurn)
        #expect(WalkDirections.maneuver(forTurn: -179) == .uTurn)
    }

    @Test func metresAreRoundedForReading() {
        #expect(WalkDirections.rounded(metres: 2) == 5)
        #expect(WalkDirections.rounded(metres: 82) == 80)
        #expect(WalkDirections.rounded(metres: 118) == 120)  // design 22: "120 m"
        #expect(WalkDirections.rounded(metres: 216) == 220)
    }

    @Test func heapPopsInPriorityOrder() {
        var heap = MinHeap()
        for (priority, vertex) in [(5.0, 5), (1.0, 1), (3.0, 3), (2.0, 2), (4.0, 4)] { heap.push(priority, vertex) }
        var order: [Int] = []
        while let vertex = heap.pop() { order.append(vertex) }
        #expect(order == [1, 2, 3, 4, 5])
    }

    @Test func routingIsFast() throws {
        let ids = [99, 15, 3, 125, 40, 90]
        let start = Date()
        var count = 0
        for a in ids { for b in ids where a != b {
            _ = router.route(from: try station(a), to: try station(b))
            count += 1
        } }
        let perRoute = Date().timeIntervalSince(start) / Double(count)
        #expect(perRoute < 0.05, "\(Int(perRoute * 1000)) ms per route")
    }

    @Test func loadingIsQuick() throws {
        let start = Date()
        _ = try WalkGraph.read(from: repoData.walkGraph)
        #expect(Date().timeIntervalSince(start) < 1.0)
    }
}
