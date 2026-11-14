import Foundation

/// Finds the timetable trip of a live departure: same station, same line, same planned minute. Both sources come
/// from NVBW, so the planned minute agrees. When several trips fit, the one whose headsign matches the destination
/// wins; a tie after that means no match, never a guess.
public struct TripMatcher: Sendable {
    public struct Match: Sendable {
        public let trip: Timetable.Trip
        public let day: Int
        public var key: String { trip.key(on: day) }
    }

    let timetable: Timetable

    public init(timetable: Timetable) {
        self.timetable = timetable
    }

    /// Whether this departure is one the server should match: a city line of the timetable.
    public func isCity(_ departure: UpstreamDeparture) -> Bool { timetable.isCityLine(departure.line) }

    public func match(_ departure: UpstreamDeparture) -> Match? {
        guard let station = timetable.station(forPlatform: departure.platform) else { return nil }
        let found = timetable.candidates(station: station, line: departure.line, planned: departure.planned)
        if found.count == 1 { return Match(trip: found[0].trip, day: found[0].day) }
        guard found.count > 1 else { return nil }
        let destination = Self.words(departure.destinationName)
        let fitting = found.filter { Self.fits(Self.words($0.trip.headsign), destination) }
        guard fitting.count == 1 else { return nil }
        return Match(trip: fitting[0].trip, day: fitting[0].day)
    }

    /// Lower-case words without accents and town names, so "Konstanz Universität" fits "Universität".
    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
        let parts = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(parts.filter { $0.count > 1 && !["konstanz", "kn", "str", "strasse", "bf", "bahnhof"].contains($0) })
    }

    static func fits(_ headsign: Set<String>, _ destination: Set<String>) -> Bool {
        !headsign.isEmpty && !destination.isEmpty && (headsign.isSubset(of: destination) || destination.isSubset(of: headsign)
            || !headsign.isDisjoint(with: destination))
    }
}
