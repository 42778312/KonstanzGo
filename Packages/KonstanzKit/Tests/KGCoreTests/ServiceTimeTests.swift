import Foundation
import Testing
@testable import KGCore

@Suite("Service-day time")
struct ServiceTimeTests {
    let clock = ServiceClock()
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()

    /// "yyyy-MM-dd HH:mm" in UTC, to check absolute moments.
    func utcText(_ date: Date) -> String {
        let p = utc.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", p.year!, p.month!, p.day!, p.hour!, p.minute!)  // swiftlint:disable:this force_unwrapping
    }

    @Test func ordinaryDayInWinter() {
        // 28 Oct 2026, CET (UTC+1): 14:21 → 13:21 UTC.
        #expect(utcText(clock.date(ServiceDay(yyyymmdd: 20261028), minutes: 14 * 60 + 21)) == "2026-10-28 13:21")
    }

    @Test func ordinaryDayInSummer() {
        // 12 Jul 2026, CEST (UTC+2).
        #expect(utcText(clock.date(ServiceDay(yyyymmdd: 20260712), minutes: 8 * 60)) == "2026-07-12 06:00")
    }

    @Test func timesPastMidnightBelongToTheNextMorning() {
        // 25:10 on 27 Oct = 01:10 on 28 Oct (CET).
        #expect(utcText(clock.date(ServiceDay(yyyymmdd: 20261027), minutes: 25 * 60 + 10)) == "2026-10-28 00:10")
        // 27:51, the latest time in the timetable.
        #expect(utcText(clock.date(ServiceDay(yyyymmdd: 20261027), minutes: 1671)) == "2026-10-28 02:51")
    }

    @Test func clocksGoBackOn25October2026() {
        // Summer time ends at 03:00 CEST → 02:00 CET.
        let day = ServiceDay(yyyymmdd: 20261025)
        #expect(utcText(clock.date(day, minutes: 1 * 60)) == "2026-10-24 23:00")   // 01:00 CEST
        #expect(utcText(clock.date(day, minutes: 8 * 60)) == "2026-10-25 07:00")   // 08:00 CET, wall clock
        #expect(utcText(clock.date(day, minutes: 23 * 60 + 59)) == "2026-10-25 22:59")
        // A night bus of 24 Oct at 26:30 = 02:30 on the 25th: happens twice; the first one is used.
        #expect(utcText(clock.date(ServiceDay(yyyymmdd: 20261024), minutes: 26 * 60 + 30)) == "2026-10-25 00:30")
    }

    @Test func clocksGoForwardOn29March2026() {
        // 02:00 CET → 03:00 CEST: 02:30 does not exist and becomes 03:30 CEST.
        let day = ServiceDay(yyyymmdd: 20260329)
        #expect(utcText(clock.date(day, minutes: 1 * 60 + 59)) == "2026-03-29 00:59")  // 01:59 CET
        #expect(utcText(clock.date(day, minutes: 2 * 60 + 30)) == "2026-03-29 01:30")  // → 03:30 CEST
        #expect(utcText(clock.date(day, minutes: 14 * 60)) == "2026-03-29 12:00")      // 14:00 CEST
    }

    @Test func runningDaysAfterMidnightIncludeYesterday() {
        let night = clock.date(ServiceDay(yyyymmdd: 20261028), minutes: 30)
        let days = clock.runningDays(at: night)
        #expect(days.count == 2)
        #expect(days[0].day == ServiceDay(yyyymmdd: 20261028) && days[0].minutes == 30)
        #expect(days[1].day == ServiceDay(yyyymmdd: 20261027) && days[1].minutes == 1470)
    }

    @Test func roundTripThroughADate() {
        let day = ServiceDay(yyyymmdd: 20261028)
        let date = clock.date(day, minutes: 14 * 60 + 35)
        let running = clock.runningDays(at: date)
        #expect(running[0].day == day && running[0].minutes == 14 * 60 + 35)
    }

    @Test func dayArithmeticCrossesMonthsYearsAndClockChanges() {
        #expect(ServiceDay(yyyymmdd: 20261031).next == ServiceDay(yyyymmdd: 20261101))
        #expect(ServiceDay(yyyymmdd: 20270101).previous == ServiceDay(yyyymmdd: 20261231))
        #expect(ServiceDay(yyyymmdd: 20261025).next == ServiceDay(yyyymmdd: 20261026))
        #expect(ServiceDay(yyyymmdd: 20260329).previous == ServiceDay(yyyymmdd: 20260328))
        #expect(ServiceDay(yyyymmdd: 20261212).yyyymmdd == 20261212)
    }

    @Test func formatWrapsAfterMidnight() {
        #expect(ServiceClock.format(minutes: 14 * 60 + 5) == "14:05")
        #expect(ServiceClock.format(minutes: 1510) == "01:10")
        #expect(ServiceClock.format(minutes: 0) == "00:00")
    }
}
