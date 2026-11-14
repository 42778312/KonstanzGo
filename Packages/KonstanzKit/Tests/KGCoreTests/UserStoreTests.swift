import Foundation
import Testing
@testable import KGCore

// Serialized: `worksAgainAfterSuspension` posts GRDB's process-wide suspend notification, which interrupts every
// open UserStore (`sqlite3_interrupt`). Run in parallel, another test's write fails with "SQLite error 9: interrupted".
@Suite("User store", .serialized)
struct UserStoreTests {
    let store: UserStore
    let sternenplatz = SavedTarget.station(id: 99, name: "Sternenplatz", coordinate: .init(latitude: 47.6676, longitude: 9.1794))
    let konzil = SavedTarget.place(id: "konzil", name: "Konzil", kind: .venue, coordinate: .init(latitude: 47.6608, longitude: 9.1790))
    let home = SavedTarget.point(name: "Seestraße 21", coordinate: .init(latitude: 47.664, longitude: 9.185))

    init() throws {
        store = try UserStore()
    }

    private func temporaryFile() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "user.sqlite")
    }

    @Test func aDamagedFileIsKeptAndANewOneStarts() throws {
        let url = try temporaryFile()
        try Data(repeating: 0x41, count: 8_192).write(to: url)
        let opened = try UserStore.openRecovering(url: url, now: Date(timeIntervalSince1970: 1_000))
        #expect(opened.recovered)
        try opened.store.setSlot(.home, to: home)
        #expect(try opened.store.favorites().count == 1)
        let kept = url.deletingLastPathComponent().appending(path: "user.sqlite.damaged-1000")
        #expect(try Data(contentsOf: kept) == Data(repeating: 0x41, count: 8_192))
    }

    @Test func aHealthyFileIsLeftAlone() throws {
        let url = try temporaryFile()
        do {
            let first = try UserStore.openRecovering(url: url)
            #expect(!first.recovered)
            try first.store.setSlot(.home, to: home)
        }
        let again = try UserStore.openRecovering(url: url)
        #expect(!again.recovered)
        #expect(try again.store.favorites().count == 1)
    }

    @Test func worksAgainAfterSuspension() throws {
        UserStore.suspend()
        UserStore.resume()
        try store.setSlot(.home, to: home)
        #expect(try store.favorites().count == 1)
    }

    @Test func slotsAreSetOnceAndReplaced() throws {
        try store.setSlot(.home, to: home)
        try store.setSlot(.home, to: konzil)
        let favorites = try store.favorites()
        #expect(favorites.count == 1)
        #expect(favorites.first?.slot == .home)
        #expect(try store.slot(.home)?.target == konzil)
        #expect(try store.slot(.work) == nil)
    }

    @Test func savingTwiceKeepsOne() throws {
        try store.addFavorite(sternenplatz)
        try store.addFavorite(sternenplatz)
        #expect(try store.favorites().count == 1)
        #expect(try store.isFavorite(sternenplatz))
        #expect(try store.isFavorite(konzil) == false)
    }

    @Test func reorderLikeSwiftUI() throws {
        let first = try store.addFavorite(sternenplatz)
        try store.addFavorite(konzil)
        try store.addFavorite(home)
        // Drag the first item to the end.
        try store.moveFavorites(from: IndexSet(integer: 0), to: 3)
        #expect(try store.favorites().map(\.displayName) == ["Konzil", "Seestraße 21", "Sternenplatz"])
        #expect(try store.favorites().map(\.order) == [0, 1, 2])
        try store.removeFavorite(id: first.id)
        #expect(try store.favorites().map(\.order) == [0, 1])
    }

    @Test func renameAndClearTheName() throws {
        let favorite = try store.addFavorite(konzil)
        try store.renameFavorite(id: favorite.id, to: "  Konzert  ")
        #expect(try store.favorites().first?.displayName == "Konzert")
        try store.renameFavorite(id: favorite.id, to: "   ")
        #expect(try store.favorites().first?.displayName == "Konzil")
    }

    @Test func recentIsNewestFirstWithoutDuplicates() throws {
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        try store.addRecent(sternenplatz, at: start)
        try store.addRecent(konzil, at: start.addingTimeInterval(60))
        try store.addRecent(sternenplatz, at: start.addingTimeInterval(120))
        #expect(try store.recent().map(\.target.name) == ["Sternenplatz", "Konzil"])
    }

    @Test func recentKeepsOnlyTheNewest50() throws {
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        for index in 0..<60 {
            try store.addRecent(.point(name: "Ort \(index)", coordinate: .init(latitude: 47.66, longitude: 9.17)),
                                at: start.addingTimeInterval(Double(index)))
        }
        let recent = try store.recent()
        #expect(recent.count == UserStore.recentLimit)
        #expect(recent.first?.target.name == "Ort 59")
        #expect(recent.last?.target.name == "Ort 10")
    }

    @Test func tripsThisWeekStartOnMonday() throws {
        let clock = ServiceClock()
        // Wed 28 Oct 2026; that week's Monday is 26 Oct.
        let wednesday = clock.date(ServiceDay(yyyymmdd: 20261028), minutes: 14 * 60)
        for day in [20261025, 20261026, 20261027, 20261028] {  // Sunday doesn't count
            try store.addFinishedTrip(FinishedTrip(date: clock.date(ServiceDay(yyyymmdd: day), minutes: 9 * 60),
                                                   lineName: "9", from: "Sternenplatz", to: "Universität"))
        }
        #expect(try store.tripsThisWeek(now: wednesday) == 3)
    }

    @Test func alarmsReplaceAndExpire() throws {
        let departure = Date(timeIntervalSince1970: 1_793_000_000)
        func alarm(_ minutes: Int) -> Alarm {
            Alarm(stationID: 99, stationName: "Sternenplatz", tripID: 7, lineName: "9", headsign: "Universität",
                  platformCode: "1", departure: departure, minutesBefore: minutes)
        }
        try store.addAlarm(alarm(2))
        try store.addAlarm(alarm(5))
        #expect(try store.upcomingAlarms(after: departure.addingTimeInterval(-3_600)).map(\.minutesBefore) == [5])
        // After it went off it is no longer upcoming; once the bus has gone it is removed.
        #expect(try store.upcomingAlarms(after: departure.addingTimeInterval(-60)).isEmpty)
        try store.removePastAlarms(before: departure.addingTimeInterval(60))
        #expect(try store.upcomingAlarms(after: .distantPast).isEmpty)
    }

    @Test func clearHistoryKeepsFavouritesAndAlarms() throws {
        try store.addFavorite(konzil)
        try store.addRecent(sternenplatz)
        try store.addFinishedTrip(FinishedTrip(date: .now, lineName: "1", from: "A", to: "B"))
        try store.clearHistory()
        #expect(try store.recent().isEmpty)
        #expect(try store.tripsThisWeek() == 0)
        #expect(try store.favorites().count == 1)
    }

    @Test func survivesReopening() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "user-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try UserStore(url: url).addFavorite(konzil)
        #expect(try UserStore(url: url).favorites().first?.target == konzil)
    }
}
