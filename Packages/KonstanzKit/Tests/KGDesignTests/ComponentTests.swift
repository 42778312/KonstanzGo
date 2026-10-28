import Foundation
import Testing
@testable import KGDesign

/// The logic inside the components: what the minutes show, and what VoiceOver reads (plan B7, B11, B22).
@Suite("Components")
struct ComponentTests {
    /// Wed 28 Oct 2026 14:18 in Konstanz, the design's "now".
    static let now: Date = {
        var parts = DateComponents(year: 2026, month: 10, day: 28, hour: 14, minute: 18)
        parts.timeZone = TimeZone(identifier: "Europe/Berlin")
        return Calendar.kgKonstanz.date(from: parts) ?? .distantPast
    }()

    /// The tests read the catalog in whichever language this machine prefers; both are checked.
    static let german = Bundle.module.preferredLocalizations.first?.hasPrefix("de") ?? true

    @Test("under a minute is jetzt")
    func now() {
        #expect(KGMinutesValue(departure: Self.now.addingTimeInterval(59), now: Self.now) == .now)
        #expect(KGMinutesValue(departure: Self.now.addingTimeInterval(-30), now: Self.now) == .now)
    }

    @Test("minutes count down, rounded down")
    func minutes() {
        #expect(KGMinutesValue(departure: Self.now.addingTimeInterval(60), now: Self.now) == .minutes(1))
        #expect(KGMinutesValue(departure: Self.now.addingTimeInterval(3 * 60 + 59), now: Self.now) == .minutes(3))
        #expect(KGMinutesValue(departure: Self.now.addingTimeInterval(59 * 60), now: Self.now) == .minutes(59))
    }

    @Test("from an hour on the clock time shows")
    func clock() {
        let later = Self.now.addingTimeInterval(60 * 60)
        #expect(KGMinutesValue(departure: later, now: Self.now) == .clock(later))
        #expect(KGStrings.clock(later) == "15:18")
    }

    @Test("a departure reads as one sentence")
    func departureSentence() {
        let sentence = KGStrings.departure(line: "9A", destination: "Universität", platform: "A",
                                           minutes: .minutes(3), isLive: false)
        if Self.german {
            #expect(sentence == "Linie 9A nach Universität, Steig A, in 3 Minuten, laut Fahrplan")
        } else {
            #expect(sentence == "Line 9A to Universität, Platform A, in 3 minutes, scheduled")
        }
    }

    @Test("one minute is singular, no platform is left out")
    func departureSingular() {
        let sentence = KGStrings.departure(line: "1", destination: "Staad", platform: nil, minutes: .minutes(1),
                                           isLive: true)
        #expect(sentence == (Self.german ? "Linie 1 nach Staad, in 1 Minute, live" : "Line 1 to Staad, in 1 minute, live"))
    }

    @Test("leg strip reads walk, line, walk")
    func legs() {
        let text = KGStrings.legs([.walk(minutes: 2), .bus(line: "9A"), .walk(minutes: 1)])
        #expect(text == (Self.german ? "2 Minuten zu Fuß, Linie 9A, 1 Minute zu Fuß"
                                     : "2 minute walk, Line 9A, 1 minute walk"))
    }

    @Test("short day label as the design: Do 29. Okt.")
    func shortDay() {
        let tomorrow = Self.now.addingTimeInterval(24 * 3600)
        #expect(KGStrings.shortDay(tomorrow, locale: Locale(identifier: "de_DE")) == "Do. 29. Okt.")
        #expect(KGStrings.shortDay(tomorrow, locale: Locale(identifier: "en_GB")) == "Thu 29 Oct")
    }
}
