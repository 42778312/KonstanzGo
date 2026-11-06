import Foundation
import Testing
@testable import KGCore

@Suite("Jetzt board")
struct NowBoardTests {
    static let transit = try? OfflineTransit(data: repoData)
    let now = ServiceClock().date(ServiceDay(yyyymmdd: 20261105), minutes: 12 * 60)
    let sternenplatz = Coordinate(latitude: 47.6665, longitude: 9.1755)

    var transit: OfflineTransit { get throws { try #require(Self.transit) } }

    @Test func adviceFollowsTheWalk() {
        func advice(_ seconds: Double, walk: Int = 5) -> LeaveAdvice {
            LeaveAdvice.forBus(leaving: now.addingTimeInterval(seconds), walkMinutes: walk, now: now)
        }
        #expect(advice(600) == .leaveIn(minutes: 4))
        #expect(advice(420) == .leaveIn(minutes: 1))
        #expect(advice(350) == .leaveNow)
        #expect(advice(320) == .hurry)
        #expect(advice(230) == .hurry)
        #expect(advice(220) == .tooLate)
    }

    private func departure(_ line: Int, _ headsign: String, in minutes: Double, status: DepartureStatus = .scheduled,
                           trip: Int = Int.random(in: 1...1_000_000)) throws -> Departure {
        let store = try transit.store
        let station = try #require(store.stations.first)
        let platform = try #require(store.platforms(of: station.id).first)
        return Departure(tripID: trip, line: Line(id: line, name: "\(line)", longName: "", isCity: true), headsign: headsign,
                         platform: platform, scheduled: now.addingTimeInterval(minutes * 60), status: status)
    }

    private func stop(_ departures: [Departure], walk: Int? = nil) throws -> NowCandidate {
        NowCandidate(station: try #require(try transit.store.stations.first), walkMinutes: walk, isSaved: false, departures: departures)
    }

    @Test func oneRowPerLineAndDirectionInRealOrder() throws {
        let board = NowBoard.stops(from: [try stop([
            try departure(1, "Staad", in: 2, status: .live(delayMinutes: 6)),
            try departure(1, "Staad", in: 10),
            try departure(5, "Uni", in: 4)
        ])], now: now)
        #expect(board.first?.rows.map(\.departure.line.name) == ["5", "1"])
    }

    @Test func aBusOutOfReachGivesWayToTheNextOne() throws {
        let board = NowBoard.stops(from: [try stop([try departure(1, "Staad", in: 2), try departure(1, "Staad", in: 12)], walk: 5)], now: now)
        let row = try #require(board.first?.rows.first)
        #expect(row.departure.scheduled == now.addingTimeInterval(720))
        #expect(row.advice == .leaveIn(minutes: 6))
    }

    @Test func cancelledAndGoneBusesAreLeftOutAndEmptyStopsSkipped() throws {
        let board = NowBoard.stops(from: [
            try stop([try departure(1, "Staad", in: 5, status: .cancelled), try departure(2, "X", in: -1)]),
            try stop([try departure(3, "Y", in: 5)])
        ], now: now)
        #expect(board.count == 1)
        #expect(board.first?.rows.first?.departure.line.name == "3")
    }

    @Test func aboutAsNearTheSoonestBusComesFirstButSavedAndFarStopsKeepTheirPlace() throws {
        let stations = try transit.store.stations
        func at(_ index: Int, walk: Int, saved: Bool = false, in minutes: Double) throws -> NowCandidate {
            NowCandidate(station: stations[index], walkMinutes: walk, isSaved: saved, departures: [try departure(index + 1, "X", in: minutes)])
        }
        let near = try at(0, walk: 2, in: 34), close = try at(1, walk: 4, in: 11), far = try at(2, walk: 12, in: 15)
        #expect(NowBoard.stops(from: [near, close, far], now: now).map(\.station.id) == [stations[1].id, stations[0].id])
        let saved = try at(3, walk: 6, saved: true, in: 50)
        #expect(NowBoard.stops(from: [near, close, saved], now: now).first?.station.id == stations[3].id)
        #expect(NowBoard.stops(from: [near, far], now: now).map(\.station.id) == [stations[0].id, stations[2].id])
    }

    @Test func noAdviceWithoutAPositionOrRightAtTheStop() throws {
        #expect(NowBoard.stops(from: [try stop([try departure(1, "S", in: 5)])], now: now).first?.rows.first?.advice == nil)
        #expect(NowBoard.stops(from: [try stop([try departure(1, "S", in: 5)], walk: 1)], now: now).first?.rows.first?.advice == nil)
    }

    @Test func nearestStopsComeWithRealBuses() throws {
        let transit = try transit
        let found = NowBoard.candidates(in: transit, near: sternenplatz, saved: [], at: now, walker: transit.walker)
        #expect(found.count >= 2)
        #expect(found.first?.walkMinutes != nil)
        let board = NowBoard.stops(from: found, now: now)
        #expect(board.count == 2)
        #expect(board.allSatisfy { !$0.rows.isEmpty })
    }

    @Test func savedStopsFirstWhenNearAndOnlyThemWithoutAPosition() throws {
        let transit = try transit
        let store = transit.store
        let saved = try #require(store.stations(near: sternenplatz, within: 800, limit: 5).last).0.id
        #expect(NowBoard.candidates(in: transit, near: sternenplatz, saved: [saved], at: now).first?.station.id == saved)
        #expect(NowBoard.candidates(in: transit, near: nil, saved: [saved], at: now).map(\.station.id) == [saved])
        #expect(NowBoard.candidates(in: transit, near: nil, saved: [], at: now).isEmpty)
    }

    @Test func aFarSavedStopDoesNotPushOutTheNearestOnes() throws {
        let transit = try transit
        let far = try #require(transit.store.stations.max { $0.coordinate.distance(to: sternenplatz) < $1.coordinate.distance(to: sternenplatz) })
        let found = NowBoard.candidates(in: transit, near: sternenplatz, saved: [far.id], at: now)
        #expect(found.first?.station.id != far.id)
    }

    @Test func isQuick() throws {
        let transit = try transit
        let start = ContinuousClock.now
        _ = NowBoard.stops(from: NowBoard.candidates(in: transit, near: sternenplatz, saved: [], at: now, walker: transit.walker), now: now)
        #expect(ContinuousClock.now - start < .milliseconds(800), "debug build")
    }
}
