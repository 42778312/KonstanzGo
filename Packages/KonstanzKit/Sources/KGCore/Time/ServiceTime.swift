import Foundation

/// A timetable day. Trips belong to the day they start on, even when they run past midnight.
/// Stored in the timetable as `yyyymmdd` (`service_date.date`).
public struct ServiceDay: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// 20261028 → 28 Oct 2026.
    public init(yyyymmdd: Int) {
        self.init(year: yyyymmdd / 10_000, month: yyyymmdd / 100 % 100, day: yyyymmdd % 100)
    }

    /// The calendar day of `date` in Konstanz.
    public init(_ date: Date, calendar: Calendar = .konstanz) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The value used in the timetable database.
    public var yyyymmdd: Int { year * 10_000 + month * 100 + day }

    public func adding(days: Int, calendar: Calendar = .konstanz) -> ServiceDay {
        let noon = ServiceClock(calendar: calendar).date(self, minutes: 12 * 60)
        return ServiceDay(calendar.date(byAdding: .day, value: days, to: noon) ?? noon, calendar: calendar)
    }

    public var previous: ServiceDay { adding(days: -1) }
    public var next: ServiceDay { adding(days: 1) }

    public static func < (lhs: ServiceDay, rhs: ServiceDay) -> Bool { lhs.yyyymmdd < rhs.yyyymmdd }

    public var description: String { String(yyyymmdd) }
}

/// Turns timetable times into real dates and back.
///
/// Timetable times are minutes after midnight of the service day and may pass 24:00 (1510 = 25:10).
/// They are read as **wall-clock times**, the way they are printed at the stop: 25:10 on 24 Oct is
/// 01:10 on 25 Oct. On the two days the clocks change this differs from GTFS's "noon minus 12 h"
/// rule only for times between midnight and 03:00; the Android app reads them the same way.
/// A time that does not exist (02:30 when the clocks go forward) becomes the next valid one (03:30).
public struct ServiceClock: Sendable {
    public static let minutesPerDay = 24 * 60
    /// How far into tomorrow's service "the next bus" looks: its night trips, not the next morning's first bus.
    public static let nightMinutes = 3 * 60

    public var calendar: Calendar

    public init(calendar: Calendar = .konstanz) {
        self.calendar = calendar
    }

    /// The moment a timetable time on a service day happens.
    public func date(_ day: ServiceDay, minutes: Int) -> Date {
        let dayOffset = Int((Double(minutes) / Double(Self.minutesPerDay)).rounded(.down))
        let wall = minutes - dayOffset * Self.minutesPerDay
        var parts = DateComponents(year: day.year, month: day.month, day: day.day + dayOffset,
                                   hour: wall / 60, minute: wall % 60)
        parts.timeZone = calendar.timeZone
        // `nextTime` style resolution: a skipped wall time moves forward by the gap.
        if let exact = calendar.date(from: parts), sameWallTime(exact, parts) {
            return exact
        }
        parts.hour = (parts.hour ?? 0) + 1
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// Which service days are running at `date`, and how late it is in each of them in timetable minutes.
    /// After midnight a trip of the previous day may still be on the road, so both are returned:
    /// at 00:30 on the 28th → (28th, 30) and (27th, 1470).
    public func runningDays(at date: Date) -> [(day: ServiceDay, minutes: Int)] {
        let today = ServiceDay(date, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return [(today, minutes), (today.previous, minutes + Self.minutesPerDay)]
    }

    /// The service days with departures still to come at `date`: the running ones and tomorrow, whose first
    /// trips leave soon after midnight. Tomorrow's minutes are negative: at 23:30 → -30, so its 00:09 (9) is later.
    public func upcomingDays(at date: Date) -> [(day: ServiceDay, minutes: Int)] {
        let running = runningDays(at: date)
        return running + [(running[0].day.next, running[0].minutes - Self.minutesPerDay)]
    }

    /// "14:05" for a timetable time (hours wrap after midnight: 1510 → "01:10").
    public static func format(minutes: Int) -> String {
        let wrapped = ((minutes % minutesPerDay) + minutesPerDay) % minutesPerDay
        let hours = wrapped / 60, mins = wrapped % 60
        return (hours < 10 ? "0" : "") + "\(hours):" + (mins < 10 ? "0" : "") + "\(mins)"
    }

    private func sameWallTime(_ date: Date, _ parts: DateComponents) -> Bool {
        let back = calendar.dateComponents([.hour, .minute], from: date)
        return back.hour == parts.hour.map { $0 % 24 } && back.minute == parts.minute
    }
}
