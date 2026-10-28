import Foundation
import Testing
@testable import KGCore

/// The bundled data in the repo: `App/Resources/Data`, found from this file's path.
let repoData = BundledData(
    root: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // KGCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // KonstanzKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
        .appending(path: "App/Resources/Data")
)

@Suite("Bundled data")
struct BundledDataTests {
    @Test("every data file exists", arguments: repoData.allFiles)
    func fileExists(_ url: URL) {
        #expect(FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) is missing")
    }

    @Test func timetableMatchesTheDataPipeline() throws {
        let info = try TimetableInfo.read(from: repoData.timetable)
        // The same numbers DataPipeline/check.py prints; they change with each new feed.
        #expect(info.stations == 142)
        #expect(info.platforms == 263)
        #expect(info.cityLines == 18)
        #expect(info.trips == 3380)
        #expect(info.validUntil == DateComponents(year: 2026, month: 12, day: 12))
        #expect(info.attribution == "Datensatz der NVBW GmbH")
    }

    @Test func walkGraphHasItsMagicHeader() throws {
        let handle = try FileHandle(forReadingFrom: repoData.walkGraph)
        defer { try? handle.close() }
        #expect(try handle.read(upToCount: 4) == Data("KWG1".utf8))
    }
}

@Suite("Days left")
struct DaysLeftTests {
    let info = TimetableInfo(
        feedVersion: "x", validFrom: DateComponents(year: 2026, month: 7, day: 12),
        validUntil: DateComponents(year: 2026, month: 12, day: 12), attribution: "",
        stations: 0, platforms: 0, cityLines: 0, trips: 0
    )

    func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        Calendar.konstanz.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test func countsWholeDaysInKonstanz() {
        #expect(info.daysLeft(from: date(2026, 10, 28)) == 45)
        #expect(info.daysLeft(from: date(2026, 12, 12)) == 0)
        #expect(info.daysLeft(from: date(2026, 12, 13)) == -1)
    }

    @Test func lateEveningIsStillTheSameDay() {
        #expect(info.daysLeft(from: date(2026, 12, 11, hour: 23)) == 1)
    }

    @Test func clocksGoingBackDoNotChangeTheCount() {
        // 25 Oct 2026: summer time ends in Germany, that day has 25 hours.
        #expect(info.daysLeft(from: date(2026, 10, 24)) == 49)
        #expect(info.daysLeft(from: date(2026, 10, 26)) == 47)
    }
}
