import Foundation
@testable import LiveCore
import Synchronization

/// A clock that only moves when someone sleeps on it.
final class ManualClock: LiveClock {
    private let current: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_794_560_000)) {
        current = Mutex(start)
    }

    func now() -> Date { current.withLock { $0 } }

    func sleep(seconds: Double) async throws {
        guard seconds > 0 else { return }
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    func advance(_ seconds: Double) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// A source that answers with a closure and counts its calls.
final class FakeSource: RealtimeSource {
    private let calls = Mutex(0)
    let answer: @Sendable (String) async throws -> [UpstreamDeparture]

    init(answer: @escaping @Sendable (String) async throws -> [UpstreamDeparture] = { _ in [] }) {
        self.answer = answer
    }

    var callCount: Int { calls.withLock { $0 } }

    func departures(stopGID: String, limit: Int) async throws -> [UpstreamDeparture] {
        calls.withLock { $0 += 1 }
        return try await answer(stopGID)
    }
}

enum Fixtures {
    static let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!

    static let timetable: Timetable = try! Timetable(path: folder.appendingPathComponent("timetable-20261011.db").path)

    /// Every recorded departure monitor response: (stop gid, file name, departures, recorded at).
    static let responses: [(gid: String, name: String, departures: [UpstreamDeparture], at: Date)] = {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("dm_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let data = try! Data(contentsOf: url)
                let gid = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { ($0["locations"] as? [[String: Any]])?.first?["id"] as? String } ?? ""
                let departures = try! EFAParser.parse(data, stopGID: gid)
                return (gid, url.lastPathComponent, departures, recordedAt(url.lastPathComponent))
            }
    }()

    /// "dm_bahnhof_20261113-1112.json" → 13 Nov 2026 11:12 in Konstanz.
    static func recordedAt(_ name: String) -> Date {
        let stamp = name.split(separator: "_").last!.replacingOccurrences(of: ".json", with: "")
        let parts = stamp.split(separator: "-")
        let day = Int(parts[0])!, time = Int(parts[1])!
        return BerlinTime.date(serviceDay: day, minute: time / 100 * 60 + time % 100)
    }
}
