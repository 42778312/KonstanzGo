import Foundation
import Observation

/// The weather at the Deutscher Wetterdienst's Konstanz station (10929), as last read: the temperature and
/// what the sky is doing. Kept on the phone, so the map shows the last reading when there is no internet.
public struct WeatherReading: Codable, Sendable, Equatable {
    /// °C, 2 m above ground.
    public var temperature: Double
    public var condition: WeatherCondition
    /// When the station measured it.
    public var observed: Date

    public init(temperature: Double, condition: WeatherCondition, observed: Date) {
        self.temperature = temperature
        self.condition = condition
        self.observed = observed
    }

    /// "7°", rounded like a weather app ("-0°" never shows).
    public var degrees: String {
        let rounded = Int(temperature.rounded())
        return "\(rounded == 0 ? 0 : rounded)°"
    }
}

/// What the sky is doing, from the station's "aktuelles Wetter" code (DWD's list of 31 codes for its
/// stations), or from cloud cover and rain when the station sent no code that hour.
public enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, heavyRain, sleet, snow, hail, thunder, wind

    public init?(dwdCode code: Int) {
        switch code {
        case 1: self = .clear
        case 2: self = .partlyCloudy
        case 3, 4: self = .cloudy
        case 5, 6: self = .fog
        case 7: self = .drizzle
        case 8, 10, 18: self = .rain
        case 9, 11, 19: self = .heavyRain
        case 12, 13, 20, 21: self = .sleet
        case 14, 15, 16, 22, 23: self = .snow
        case 17, 24, 25: self = .hail
        case 26 ... 30: self = .thunder
        case 31: self = .wind
        default: return nil
        }
    }

    /// Without a code: rain in the last hour, else how much of the sky is covered (in eighths, as % here).
    public init(cloudCover: Double?, rainLastHour: Double?) {
        if let rain = rainLastHour, rain > 0 {
            self = rain >= 2.5 ? .heavyRain : .rain
        } else if let cover = cloudCover {
            self = cover <= 20 ? .clear : cover <= 70 ? .partlyCloudy : .cloudy
        } else {
            self = .cloudy
        }
    }

    /// The SF Symbol for it, with the moon instead of the sun at night.
    public func symbol(night: Bool) -> String {
        switch self {
        case .clear: night ? "moon.stars.fill" : "sun.max.fill"
        case .partlyCloudy: night ? "cloud.moon.fill" : "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .sleet: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .hail: "cloud.hail.fill"
        case .thunder: "cloud.bolt.rain.fill"
        case .wind: "wind"
        }
    }
}

/// Reads DWD's open "weather_reports/poi" file for a station: three header lines (names, units, German
/// names), then one line per hour, newest first, "---" where nothing was measured.
public enum DWDReport {
    /// Konstanz's station file, about 7 KB, updated every hour.
    public static let konstanz = URL(string: "https://opendata.dwd.de/weather/weather_reports/poi/10929-BEOB.csv")!

    public static func parse(_ text: String) -> WeatherReading? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: ";", omittingEmptySubsequences: false) }
        guard lines.count > 3 else { return nil }
        let names = lines[0].map { String($0).trimmingCharacters(in: .whitespaces) }
        func column(_ name: String) -> Int? { names.firstIndex(of: name) }
        guard let temperatureColumn = column("dry_bulb_temperature_at_2_meter_above_ground") else { return nil }
        for row in lines.dropFirst(3) {
            func value(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let text = row[index].trimmingCharacters(in: .whitespaces)
                return text == "---" || text.isEmpty ? nil : text
            }
            func number(_ index: Int?) -> Double? { value(index).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } }
            guard let temperature = number(temperatureColumn),
                  let date = value(0), let time = value(1), let observed = utc(date: date, time: time) else { continue }
            let condition = number(column("present_weather")).flatMap { WeatherCondition(dwdCode: Int($0)) }
                ?? WeatherCondition(cloudCover: number(column("cloud_cover_total")),
                                    rainLastHour: number(column("precipitation_amount_last_hour")))
            return WeatherReading(temperature: temperature, condition: condition, observed: observed)
        }
        return nil
    }

    /// "30.10.26" and "19:00", in UTC.
    private static func utc(date: String, time: String) -> Date? {
        let day = date.split(separator: ".").compactMap { Int($0) }
        let clock = time.split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, clock.count == 2 else { return nil }
        var parts = DateComponents(year: 2000 + day[2], month: day[1], day: day[0], hour: clock[0], minute: clock[1])
        parts.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: parts)
    }
}

public enum SunPosition {
    /// Whether the sun is below the horizon at a place and moment (NOAA's simple solar position formula,
    /// good to a few minutes), so the weather shows a moon at night.
    public static func isNight(at date: Date, latitude: Double = 47.66, longitude: Double = 9.17) -> Bool {
        elevation(at: date, latitude: latitude, longitude: longitude) < -0.833
    }

    /// The sun's height above the horizon in degrees.
    public static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let days = date.timeIntervalSince1970 / 86400 - 10957.5 // since 2000-01-01 12:00 UTC
        let meanLongitude = (280.460 + 0.9856474 * days).truncatingRemainder(dividingBy: 360)
        let anomaly = (357.528 + 0.9856003 * days).truncatingRemainder(dividingBy: 360) * .pi / 180
        let eclipticLongitude = (meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * .pi / 180
        let obliquity = (23.439 - 0.0000004 * days) * .pi / 180
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let siderealHours = (18.697374558 + 24.06570982441908 * days).truncatingRemainder(dividingBy: 24)
        let hourAngle = siderealHours * 15 * .pi / 180 + longitude * .pi / 180 - rightAscension
        let lat = latitude * .pi / 180
        return asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)) * 180 / .pi
    }
}

/// The latest reading: the one kept on the phone at once, a fresh one from DWD when the phone is online.
/// It asks at most every 20 minutes (the station reports hourly), so many phones stay a small load.
@MainActor
@Observable
public final class WeatherModel {
    public private(set) var reading: WeatherReading?
    private var lastAsked = Date.distantPast
    private let defaults: UserDefaults
    private let fetch: @Sendable () async throws -> Data
    private static let key = "kg.weather.reading"
    static let interval: TimeInterval = 20 * 60

    public init(defaults: UserDefaults = .standard,
                fetch: @escaping @Sendable () async throws -> Data = WeatherModel.download) {
        self.defaults = defaults
        self.fetch = fetch
        reading = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(WeatherReading.self, from: $0) }
    }

    /// Asks DWD unless it was asked recently; without internet nothing changes and the last reading stays.
    public func refresh(now: Date = .now) async {
        guard now.timeIntervalSince(lastAsked) >= Self.interval else { return }
        lastAsked = now
        guard let data = try? await fetch(), let text = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8),
              let new = DWDReport.parse(text) else {
            // Offline or a bad answer: try again in two minutes, not twenty.
            lastAsked = now.addingTimeInterval(-Self.interval + 120)
            return
        }
        if reading.map({ new.observed >= $0.observed }) ?? true {
            reading = new
            defaults.set(try? JSONEncoder().encode(new), forKey: Self.key)
        }
    }

    /// Keeps asking while the map is open.
    public func keepFresh() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(120))
        }
    }

    public nonisolated static func download() async throws -> Data {
        var request = URLRequest(url: DWDReport.konstanz, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("KonstanzGo (iOS; konstant@werkflow.cc)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
