import Foundation

// A table of the design's literal rows: kept one row per line, as on the artboards, so it can be checked by eye.
// swiftlint:disable large_tuple line_length

/// The design's own examples (artboards 07–27), for previews and snapshot tests, so every screen can be put
/// next to its artboard with the same stops, lines and times. Not real data: the design's line "9A" is line 9
/// in the timetable, and some stops are placed by hand along its road.
///
/// The design's numbers fit together at **Wednesday 28 Oct 2026, 14:18** (`DesignSample.now`): 9A in 3 min is
/// 14:21, line 1 in 6 is 14:24, line 5 in 11 is 14:29, as on the stop's "Abfahrten" and "Linien" tabs.
public final class DesignSample: TransitService {
    public static let day = ServiceDay(yyyymmdd: 20261028)
    public static let now = ServiceClock().date(day, minutes: 14 * 60 + 18)

    // MARK: Stops and lines

    public static func stop(_ id: Int, _ name: String, _ lat: Double, _ lon: Double) -> Station {
        Station(id: id, name: name, shortName: name, coordinate: Coordinate(latitude: lat, longitude: lon))
    }

    public static let sternenplatz = stop(99, "Sternenplatz", 47.66756, 9.17943)
    public static let bahnhof = stop(15, "Bahnhof", 47.65871, 9.17717)
    public static let universitaet = stop(103, "Universität", 47.68961, 9.18602)
    public static let staad = stop(95, "Staad", 47.68198, 9.21020)
    public static let riedstrasse = stop(80, "Riedstraße", 47.68441, 9.14742)
    public static let petershausen = stop(9_001, "Petershausen", 47.67080, 9.18120)
    public static let petershausenBahnhof = stop(9_002, "Petershausen Bahnhof", 47.67000, 9.18180)
    public static let jahnstrasse = stop(9_003, "Jahnstraße", 47.67420, 9.18310)
    public static let mainaustrasse = stop(9_004, "Mainaustraße", 47.67750, 9.18420)
    public static let egg = stop(9_005, "Egg", 47.68170, 9.18560)
    public static let marktstaette = stop(9_006, "Marktstätte", 47.65920, 9.17580)

    public static let line9A = Line(id: 9, name: "9A", longName: "Bahnhof – Universität", isCity: true)
    public static let line1 = Line(id: 1, name: "1", longName: "Staad – Bahnhof", isCity: true)
    public static let line5 = Line(id: 5, name: "5", longName: "Petershausen – Bahnhof", isCity: true)

    public static func platform(_ station: Station, _ code: String?) -> Platform {
        Platform(id: station.id * 10 + (code.map { Int($0.unicodeScalars.first?.value ?? 0) } ?? 0),
                 stationID: station.id, code: code, coordinate: station.coordinate, direction: nil)
    }

    public static func at(_ hour: Int, _ minute: Int) -> Date {
        ServiceClock().date(day, minutes: hour * 60 + minute)
    }

    public init() {}

    public let stations = [sternenplatz, bahnhof, universitaet, staad, riedstrasse, petershausen,
                           petershausenBahnhof, jahnstrasse, mainaustrasse, egg, marktstaette]

    public var timetableInfo: TimetableInfo? {
        TimetableInfo(feedVersion: "20261011", validFrom: DateComponents(year: 2026, month: 7, day: 12),
                      validUntil: DateComponents(year: 2026, month: 12, day: 12), attribution: "Datensatz der NVBW GmbH",
                      stations: 142, platforms: 263, cityLines: 18, trips: 3_380)
    }

    public func station(id: Int) -> Station? { stations.first { $0.id == id } }

    public func stations(near point: Coordinate, within metres: Double, limit: Int) -> [(Station, Double)] {
        Array(stations.map { ($0, $0.coordinate.distance(to: point)) }.filter { $0.1 <= metres }
            .sorted { $0.1 < $1.1 }.prefix(limit))
    }

    // MARK: Departures (screens 07, 09, 12)

    /// Screen 09: 9A Universität (A) 3, 1 Staad (B) 6, 5 Petershausen (A) 11, 9A 18, 1 21 minutes from 14:18.
    public func departures(at stationID: Int, from date: Date, limit: Int) throws -> [Departure] {
        let rows: [(Line, String, String?, Int, Int)]
        switch stationID {
        case Self.sternenplatz.id:
            rows = [(Self.line9A, "Universität", "A", 14, 21), (Self.line1, "Staad", "B", 14, 24),
                    (Self.line5, "Petershausen", "A", 14, 29), (Self.line9A, "Universität", "A", 14, 36),
                    (Self.line1, "Staad", "B", 14, 39), (Self.line5, "Petershausen", "A", 14, 44),
                    (Self.line9A, "Universität", "A", 14, 51), (Self.line1, "Staad", "B", 14, 54),
                    (Self.line5, "Petershausen", "A", 14, 59)]
        case Self.bahnhof.id:
            // Screen 12 "Meine Haltestellen": 5 in 4, 9A in 9.
            rows = [(Self.line5, "Petershausen", "3", 14, 22), (Self.line9A, "Universität", "1", 14, 27),
                    (Self.line1, "Staad", "2", 14, 33)]
        default:
            rows = []
        }
        guard let station = station(id: stationID) else { return [] }
        return Array(rows.enumerated().map { index, row in
            Departure(tripID: 100 + index, line: row.0, headsign: row.1, platform: Self.platform(station, row.2),
                      scheduled: Self.at(row.3, row.4))
        }.filter { $0.scheduled >= date }.prefix(limit))
    }

    public func departuresByLine(at stationID: Int, from date: Date) throws -> [LineDirection] {
        let all = try departures(at: stationID, from: date, limit: 50)
        var groups: [LineDirection] = []
        for departure in all {
            if let index = groups.firstIndex(where: { $0.line == departure.line && $0.headsign == departure.headsign }) {
                if groups[index].departures.count < 3 { groups[index].departures.append(departure) }
            } else {
                groups.append(LineDirection(line: departure.line, headsign: departure.headsign, departures: [departure]))
            }
        }
        return groups.sorted { LineOrder.precedes($0.line.name, $1.line.name) }
    }

    public func lines(at stationID: Int) throws -> [Line] {
        stationID == Self.sternenplatz.id || stationID == Self.bahnhof.id ? [Self.line1, Self.line5, Self.line9A] : []
    }

    // MARK: Trip (screen 17)

    /// Bus 9A Richtung Universität, Sternenplatz 14:35 (Steig D) to Universität 14:52.
    public func trip(id: Int, on day: ServiceDay) throws -> Trip? {
        let calls: [(Station, Int)] = [(Self.sternenplatz, 35), (Self.petershausenBahnhof, 38), (Self.jahnstrasse, 41),
                                       (Self.mainaustrasse, 44), (Self.egg, 48), (Self.riedstrasse, 50),
                                       (Self.universitaet, 52)]
        let stops = calls.map { station, minute in
            TripStop(station: station, platform: Self.platform(station, station == Self.sternenplatz ? "D" : nil),
                     arrival: Self.at(14, minute), departure: Self.at(14, minute))
        }
        return Trip(id: id, line: Self.line9A, headsign: "Universität", stops: stops, shape: stops.map(\.platform.coordinate))
    }

    // MARK: Journeys (screens 10, 11, 21, 22)

    /// Screen 10: 14:21–14:35 fastest (walk 2 · 9A · walk 1), 14:24–14:42 with a change at Bahnhof (walk 4 · 1 · 5),
    /// 14:36–14:50 least walking (walk 1 · 9A).
    public func plan(_ request: PlanRequest) throws -> [Journey] {
        [Self.fastestJourney, Self.changeJourney, Self.leastWalkingJourney]
    }

    static func ride(_ line: Line, _ headsign: String, _ calls: [(Station, String?, Int, Int)]) -> RideLeg {
        RideLeg(tripID: line.id * 10_000 + calls[0].2 * 60 + calls[0].3, line: line, headsign: headsign,
                stops: calls.map { station, code, hour, minute in
                    TripStop(station: station, platform: platform(station, code), arrival: at(hour, minute),
                             departure: at(hour, minute))
                })
    }

    static func walk(_ from: (Int, Int), _ to: (Int, Int), metres: Int, to name: String,
                     steps: [WalkStep] = []) -> Leg {
        .walk(WalkLeg(start: at(from.0, from.1), end: at(to.0, to.1), metres: metres, destinationName: name,
                      steps: steps))
    }

    /// Screen 22: "Fußweg zum Sternenplatz · 3 Min. · 220 m · 14:18 – 14:21".
    public static let walkToSternenplatz: [WalkStep] = [
        WalkStep(maneuver: .depart, street: "Fischmarkt", way: .pedestrian, metres: 80, start: marktstaette.coordinate),
        WalkStep(maneuver: .right, street: "Bahnhofstraße", metres: 120, start: marktstaette.coordinate),
        WalkStep(maneuver: .cross, street: "Konzilstraße", way: .crossing, metres: 15, start: sternenplatz.coordinate),
        WalkStep(maneuver: .arrive, street: nil, metres: 0, start: sternenplatz.coordinate),
    ]

    /// Screen 11: Sternenplatz 14:21 → Petershausen → Jahnstraße 14:27 → Egg 14:31 → Universität 14:35.
    public static let ride9A = ride(line9A, "Universität", [
        (sternenplatz, "D", 14, 21), (petershausen, nil, 14, 24), (jahnstrasse, nil, 14, 27), (egg, nil, 14, 31),
        (universitaet, nil, 14, 35),
    ])

    /// Walk 14:18–14:21 (screen 22), 9A 14:21–14:35 (screen 11), a minute's walk (screen 10's icons).
    /// The card shows 14:21 – 14:35: cards count from the first bus (see Design/README.md).
    public static let fastestJourney = Journey(legs: [
        walk((14, 18), (14, 21), metres: 220, to: "Sternenplatz", steps: walkToSternenplatz),
        .ride(ride9A),
        walk((14, 35), (14, 36), metres: 70, to: "Universität"),
    ])

    public static let changeJourney = Journey(legs: [
        walk((14, 20), (14, 24), metres: 300, to: "Sternenplatz"),
        .ride(ride(line1, "Bahnhof", [(sternenplatz, "B", 14, 24), (bahnhof, "2", 14, 30)])),
        .ride(ride(line5, "Petershausen", [(bahnhof, "3", 14, 32), (universitaet, nil, 14, 42)])),
    ])

    public static let leastWalkingJourney = Journey(legs: [
        walk((14, 35), (14, 36), metres: 70, to: "Sternenplatz"),
        .ride(ride(line9A, "Universität", [(sternenplatz, "A", 14, 36), (universitaet, nil, 14, 50)])),
    ])

    // MARK: Search, places, map (screens 08, 15, 16)

    public static let konzil = Place(id: "konzil", name: "Konzil", kind: .venue, category: "Event venue",
                                     categoryGerman: "Veranstaltungsort", area: "Am Hafen, Konstanz",
                                     address: "Hafenstraße 2", coordinate: Coordinate(latitude: 47.66099, longitude: 9.17819))
    public static let universityPlace = Place(id: "universitaet-konstanz", name: "Universität Konstanz", kind: .university,
                                              category: "University", categoryGerman: "Universität",
                                              area: "Königsbau, Konstanz", address: "Universitätsstraße 10",
                                              coordinate: Coordinate(latitude: 47.68996, longitude: 9.18826))
    public static let universityStreet = Place(id: "universitaetsstrasse", name: "Universitätsstraße", kind: .street,
                                               category: "Street", categoryGerman: "Straße", area: "Egg, Konstanz",
                                               coordinate: Coordinate(latitude: 47.6880, longitude: 9.1850))

    /// Screen 08: "Uni" → Universität (stop, 9A), Universität Konstanz, Universitätsstraße.
    public func search(_ query: String, near point: Coordinate) -> [SearchResult] {
        guard !SearchText.tokens(query).isEmpty else { return [] }
        let all: [SearchResult] = [
            SearchResult(target: .station(Self.universitaet, lines: [Self.line9A]), match: nil, score: 3),
            SearchResult(target: .place(Self.universityPlace), match: nil, score: 2),
            SearchResult(target: .place(Self.universityStreet), match: nil, score: 1),
            SearchResult(target: .place(Self.konzil), match: nil, score: 0),
        ]
        return all.compactMap { result in
            guard let match = SearchText.highlight(in: result.name, typed: query) else { return nil }
            var result = result
            result.match = match
            return result
        }
    }

    /// Screen 16: "Seestraße · Konstanz", nearest stop Sternenplatz, 3 Min. zu Fuß.
    public func whereabouts(at point: Coordinate) -> Whereabouts {
        Whereabouts(street: "Seestraße", town: "Konstanz", coordinate: point, nearestStation: Self.sternenplatz,
                    walkMinutes: 3)
    }

    /// Screen 07: buses 5, 9A and 1 on the map.
    public func vehicles(at date: Date) throws -> [VehiclePosition] {
        [(Self.line5, "Petershausen", 47.6640, 9.1780, 20.0), (Self.line9A, "Universität", 47.6720, 9.1830, 15.0),
         (Self.line1, "Staad", 47.6620, 9.1760, 200.0)].enumerated().map { index, bus in
            VehiclePosition(tripID: index + 1, line: bus.0, headsign: bus.1,
                            coordinate: Coordinate(latitude: bus.2, longitude: bus.3), heading: bus.4, isEstimated: true)
        }
    }

    public func walk(from start: Coordinate, to end: Coordinate) -> WalkRoute? {
        WalkRoute(path: [start, end], metres: 220, steps: Self.walkToSternenplatz)
    }

    // MARK: User data (screens 12, 18)

    /// Screen 12: Zuhause and Uni set, Arbeit not; saved stops Sternenplatz and Bahnhof.
    public static func favorites() -> [Favorite] {
        [
            Favorite(slot: .home, target: .point(name: "Seestraße 21", coordinate: Coordinate(latitude: 47.66645, longitude: 9.18086)),
                     order: 0),
            Favorite(slot: .uni, target: .place(id: universityPlace.id, name: universityPlace.name, kind: .university,
                                                coordinate: universityPlace.coordinate), order: 1),
            Favorite(target: .station(id: sternenplatz.id, name: sternenplatz.name, coordinate: sternenplatz.coordinate),
                     order: 2),
            Favorite(target: .station(id: bahnhof.id, name: bahnhof.name, coordinate: bahnhof.coordinate), order: 3),
        ]
    }

    /// Screen 18: Bahnhof today, Konzil yesterday, Marktstätte and Universität Monday, Fähre Staad 21 Oct,
    /// Seestraße 21 on 19 Oct.
    public static func recent() -> [RecentItem] {
        let clock = ServiceClock()
        func on(_ yyyymmdd: Int) -> Date { clock.date(ServiceDay(yyyymmdd: yyyymmdd), minutes: 12 * 60) }
        return [
            RecentItem(target: .station(id: bahnhof.id, name: "Bahnhof", coordinate: bahnhof.coordinate), date: on(20261028)),
            RecentItem(target: .place(id: konzil.id, name: "Konzil", kind: .venue, coordinate: konzil.coordinate),
                       date: on(20261027)),
            RecentItem(target: .station(id: marktstaette.id, name: "Marktstätte", coordinate: marktstaette.coordinate),
                       date: on(20261026)),
            RecentItem(target: .place(id: universityPlace.id, name: universityPlace.name, kind: .university,
                                      coordinate: universityPlace.coordinate), date: on(20261026)),
            RecentItem(target: .station(id: staad.id, name: "Fähre Staad", coordinate: staad.coordinate), date: on(20261021)),
            RecentItem(target: .point(name: "Seestraße 21", coordinate: Coordinate(latitude: 47.66645, longitude: 9.18086)),
                       date: on(20261019)),
        ]
    }
}
// swiftlint:enable large_tuple line_length
