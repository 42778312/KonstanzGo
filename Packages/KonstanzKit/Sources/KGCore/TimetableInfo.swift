import Foundation
import GRDB

/// What the bundled timetable is: its source, the dates it covers and how big it is.
/// Read from the `meta` table and a few counts. Used by the offline-data screen and the release check.
public struct TimetableInfo: Sendable, Equatable {
    public var feedVersion: String
    /// First and last day the timetable has trips for (local calendar days).
    public var validFrom: DateComponents
    public var validUntil: DateComponents
    public var attribution: String
    public var stations: Int
    public var platforms: Int
    public var cityLines: Int
    public var trips: Int

    public init(
        feedVersion: String, validFrom: DateComponents, validUntil: DateComponents, attribution: String,
        stations: Int, platforms: Int, cityLines: Int, trips: Int
    ) {
        self.feedVersion = feedVersion
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.attribution = attribution
        self.stations = stations
        self.platforms = platforms
        self.cityLines = cityLines
        self.trips = trips
    }

    /// Days from `today` until the timetable ends (0 on its last day, negative after it).
    public func daysLeft(from today: Date, calendar: Calendar = .konstanz) -> Int {
        guard let end = calendar.date(from: validUntil) else { return 0 }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: end).day ?? 0
    }
}

extension TimetableInfo {
    /// Reads the info from a timetable database file, opened read-only.
    public static func read(from url: URL) throws -> TimetableInfo {
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        return try queue.read { db in
            let meta = try Dictionary(
                uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT key, value FROM meta").map {
                    ($0["key"] as String, $0["value"] as String)
                }
            )
            func count(_ sql: String) throws -> Int { try Int.fetchOne(db, sql: sql) ?? 0 }
            return TimetableInfo(
                feedVersion: meta["feed_version"] ?? "",
                validFrom: try day(meta["feed_start"]),
                validUntil: try day(meta["feed_end"]),
                attribution: meta["attribution"] ?? "",
                stations: try count("SELECT count(*) FROM station"),
                platforms: try count("SELECT count(*) FROM platform"),
                cityLines: try count("SELECT count(*) FROM route WHERE is_city = 1"),
                trips: try count("SELECT count(*) FROM trip")
            )
        }
    }

    /// "20261212" → year 2026, month 12, day 12.
    private static func day(_ text: String?) throws -> DateComponents {
        guard let text, text.count == 8, let n = Int(text) else {
            throw TimetableError.badMeta(text ?? "nil")
        }
        return DateComponents(year: n / 10_000, month: n / 100 % 100, day: n % 100)
    }
}

public enum TimetableError: Error, Equatable {
    case badMeta(String)
}

extension Calendar {
    /// Gregorian calendar in Konstanz's time zone. All timetable days are counted in it.
    public static let konstanz: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // A fixed IANA name present on every Apple OS; falling back to another zone would be wrong.
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
}
