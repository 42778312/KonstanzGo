import Foundation

/// The timetable's clock: wall-clock minutes in Europe/Berlin after the start of a service day. Values of 1440 and
/// more are after midnight (1510 on 27 Oct is 01:10 on 28 Oct), as printed at the stop, on clock-change days too.
public enum BerlinTime {
    public static let zone = TimeZone(identifier: "Europe/Berlin")!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }()

    /// The calendar day (yyyyMMdd) and wall-clock minute of a moment.
    public static func wallClock(of date: Date) -> (day: Int, minute: Int) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
        return (day, (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// The moment a timetable time happens: `minute` wall-clock minutes after midnight of `serviceDay`.
    public static func date(serviceDay: Int, minute: Int) -> Date {
        let extraDays = minute / 1440, rest = minute % 1440
        let start = DateComponents(year: serviceDay / 10_000, month: serviceDay / 100 % 100, day: serviceDay % 100,
                                   hour: rest / 60, minute: rest % 60)
        let base = calendar.date(from: start) ?? Date(timeIntervalSince1970: 0)
        return calendar.date(byAdding: .day, value: extraDays, to: base) ?? base
    }

    /// The day before a yyyyMMdd day.
    public static func previousDay(_ day: Int) -> Int {
        let date = self.date(serviceDay: day, minute: 12 * 60)
        let previous = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        return wallClock(of: previous).day
    }

    /// The ways a moment can be written as a timetable time: on its own calendar day, and as 24:00+ on the day
    /// before. A trip matches if it runs on that service day and stops at that minute.
    public static func serviceTimes(of date: Date) -> [(day: Int, minute: Int)] {
        let (day, minute) = wallClock(of: date)
        return [(day, minute), (previousDay(day), minute + 1440)]
    }
}
