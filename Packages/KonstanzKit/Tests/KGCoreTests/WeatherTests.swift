import Foundation
import Testing
@testable import KGCore

/// DWD's Konstanz station file read into the map's weather, the night moon, and the kept last reading.
@Suite("Weather")
struct WeatherTests {
    /// The top of the real file of 30 Oct 2026 (columns trimmed to the ones the app reads, and two more).
    static let report = """
    surface observations;Parameter description;cloud_cover_total;dry_bulb_temperature_at_2_meter_above_ground;\
    precipitation_amount_last_hour;present_weather;relative_humidity
    10929;Unit;%;Grad C;mm;CODE_TABLE;%
    Datum;Uhrzeit (UTC);Wolkenbedeckung;Temperatur (2m);Niederschlag (letzte Stunde);aktuelles Wetter;Relative Feuchte
    30.10.26;20:00;---;---;---;---;---
    30.10.26;19:00;13;8,9;0;1;73
    30.10.26;18:00;50;9;0;3;72
    """

    @Test("reads the newest hour with a temperature")
    func parsesNewest() throws {
        let reading = try #require(DWDReport.parse(Self.report))
        #expect(reading.temperature == 8.9)
        #expect(reading.degrees == "9°")
        #expect(reading.condition == .clear)
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: reading.observed)
        #expect((parts.year, parts.month, parts.day, parts.hour) == (2026, 10, 30, 19))
    }

    @Test("without a code, rain and clouds decide")
    func fallsBack() throws {
        let noCode = Self.report.replacingOccurrences(of: "13;8,9;0;1;73", with: "100;-0,3;1,2;---;90")
        let reading = try #require(DWDReport.parse(noCode))
        #expect(reading.condition == .rain)
        #expect(reading.degrees == "0°")
        #expect(WeatherCondition(cloudCover: 10, rainLastHour: 0) == .clear)
        #expect(WeatherCondition(cloudCover: 88, rainLastHour: nil) == .cloudy)
    }

    @Test("DWD's codes", arguments: [(1, WeatherCondition.clear), (2, .partlyCloudy), (4, .cloudy), (5, .fog),
                                     (8, .rain), (15, .snow), (27, .thunder), (31, .wind)])
    func codes(_ code: Int, _ condition: WeatherCondition) {
        #expect(WeatherCondition(dwdCode: code) == condition)
    }

    @Test("a garbled file gives nothing")
    func garbled() {
        #expect(DWDReport.parse("<html>Service unavailable</html>") == nil)
    }

    @Test("the moon at night in Konstanz, the sun by day")
    func night() {
        let utc = { (hour: Int) in
            Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                                                     year: 2026, month: 10, day: 30, hour: hour))!
        }
        #expect(SunPosition.isNight(at: utc(19)))
        #expect(SunPosition.isNight(at: utc(3)))
        #expect(!SunPosition.isNight(at: utc(11)))
        #expect(WeatherCondition.clear.symbol(night: true) == "moon.stars.fill")
        #expect(WeatherCondition.clear.symbol(night: false) == "sun.max.fill")
    }

    @Test("online it updates and keeps the reading; offline the last one stays")
    @MainActor
    func keepsLast() async throws {
        let defaults = try #require(UserDefaults(suiteName: "weather-\(UUID().uuidString)"))
        let report = Data(Self.report.utf8)
        let online = WeatherModel(defaults: defaults) { report }
        #expect(online.reading == nil)
        await online.refresh()
        #expect(online.reading?.degrees == "9°")

        // Next start without internet: the kept reading shows at once and stays.
        let offline = WeatherModel(defaults: defaults) { throw URLError(.notConnectedToInternet) }
        #expect(offline.reading?.degrees == "9°")
        await offline.refresh()
        #expect(offline.reading?.degrees == "9°")
    }

    @Test("an old reading isn't shown, and a new start doesn't ask again within 20 minutes")
    @MainActor
    func age() async throws {
        let defaults = try #require(UserDefaults(suiteName: "weather-\(UUID().uuidString)"))
        let report = Data(Self.report.utf8)
        let calls = Counter()
        let model = WeatherModel(defaults: defaults) { await calls.add(); return report }
        let start = Date.now
        await model.refresh(now: start)
        let reading = try #require(model.reading)
        #expect(reading.isFresh(at: reading.observed.addingTimeInterval(5 * 3600)))
        #expect(!reading.isFresh(at: reading.observed.addingTimeInterval(7 * 3600)))
        let again = WeatherModel(defaults: defaults) { await calls.add(); return report }
        await again.refresh(now: start.addingTimeInterval(60))
        #expect(await calls.count == 1)
    }

    @Test("asks DWD at most every 20 minutes, sooner again after a failure")
    @MainActor
    func throttles() async throws {
        let defaults = try #require(UserDefaults(suiteName: "weather-\(UUID().uuidString)"))
        let calls = Counter()
        let model = WeatherModel(defaults: defaults) {
            await calls.add()
            throw URLError(.notConnectedToInternet)
        }
        let start = Date.now
        await model.refresh(now: start)
        await model.refresh(now: start.addingTimeInterval(60))
        #expect(await calls.count == 1)
        await model.refresh(now: start.addingTimeInterval(125))
        #expect(await calls.count == 2)
    }
}

private actor Counter {
    var count = 0
    func add() { count += 1 }
}

@Suite("Rain advice")
struct RainAdviceTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func stop(_ id: Int, minutes: Double) -> TripStop {
        let spot = Coordinate(latitude: 47.66, longitude: 9.17)
        let time = start.addingTimeInterval(minutes * 60)
        return TripStop(station: Station(id: id, name: "\(id)", shortName: "\(id)", coordinate: spot),
                        platform: Platform(id: id, stationID: id, code: nil, coordinate: spot, direction: nil),
                        arrival: time, departure: time)
    }

    /// Walks, then rides, ending `arrives` minutes from the start.
    private func journey(walk: Double, arrives: Double, trip: Int) -> Journey {
        Journey(legs: [
            .walk(WalkLeg(start: start, end: start.addingTimeInterval(walk * 60), metres: Int(walk) * 80, destinationName: "A")),
            .ride(RideLeg(tripID: trip, line: Line(id: 1, name: "9A", longName: "", isCity: true), headsign: "B",
                          stops: [stop(trip * 10, minutes: walk), stop(trip * 10 + 1, minutes: arrives)])),
        ])
    }

    private func rain(_ condition: WeatherCondition = .rain, ageHours: Double = 0.5) -> WeatherReading {
        WeatherReading(temperature: 8, condition: condition, observed: start.addingTimeInterval(-ageHours * 3600))
    }

    private var options: [Journey] { [journey(walk: 8, arrives: 20, trip: 1), journey(walk: 2, arrives: 25, trip: 2)] }

    @Test func rainSuggestsLessWalking() {
        let advice = JourneyPlanner.rainAdvice(for: options, weather: rain(), at: start)
        #expect(advice == RainAdvice(journeyID: options[1].id, minutesSaved: 6))
    }

    @Test func oldOrDryWeatherChangesNothing() {
        #expect(JourneyPlanner.rainAdvice(for: options, weather: rain(ageHours: 3), at: start) == nil)
        #expect(JourneyPlanner.rainAdvice(for: options, weather: rain(.cloudy), at: start) == nil)
        #expect(JourneyPlanner.rainAdvice(for: options, weather: nil, at: start) == nil)
    }

    @Test func notWorthItIsNotSuggested() {
        let small = [journey(walk: 4, arrives: 20, trip: 1), journey(walk: 2, arrives: 22, trip: 2)]
        #expect(JourneyPlanner.rainAdvice(for: small, weather: rain(), at: start) == nil)
        let late = [journey(walk: 8, arrives: 20, trip: 1), journey(walk: 2, arrives: 45, trip: 2)]
        #expect(JourneyPlanner.rainAdvice(for: late, weather: rain(), at: start) == nil)
    }
}
