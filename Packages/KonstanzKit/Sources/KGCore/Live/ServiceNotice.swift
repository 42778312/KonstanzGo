import Foundation

/// A disruption from the operator: road works, a closed stop, a changed line. Stays on the phone, so the
/// app knows about it offline until it ends.
public struct ServiceNotice: Codable, Sendable, Hashable, Identifiable {
    public struct Period: Codable, Sendable, Hashable {
        public var from: Date
        public var to: Date

        public init(from: Date, to: Date) {
            self.from = from
            self.to = to
        }
    }

    public var id: String
    /// Goes up when the operator changes the notice, so a changed one is announced again.
    public var version: Int
    public var text: String
    /// The lines it names ("1", "5", "9"). Empty: every line.
    public var lines: [String]
    /// Stops it names, as the app's stop numbers.
    public var stations: [Int]
    /// The named stops aren't served. Only then do they get an X and leave routes.
    public var closesStops: Bool
    /// Where to go instead: the stops the operator names, or else the nearest ones.
    public var alternatives: [Int]
    public var periods: [Period]

    public init(id: String, version: Int = 1, text: String, lines: [String] = [], stations: [Int] = [],
                closesStops: Bool = false, alternatives: [Int] = [], periods: [Period]) {
        self.id = id
        self.version = version
        self.text = text
        self.lines = lines
        self.stations = stations
        self.closesStops = closesStops
        self.alternatives = alternatives
        self.periods = periods
    }

    public func isActive(at date: Date) -> Bool {
        periods.contains { $0.from <= date && date < $0.to }
    }

    /// When the current period ends.
    public func end(after date: Date) -> Date? {
        periods.first { $0.from <= date && date < $0.to }?.to
    }

    /// Identifies this wording of the notice, for "already told the user".
    public var seenKey: String { "\(id)#\(version)" }
}

/// Which stops aren't served at one moment, and for which lines.
public struct StopClosures: Sendable, Hashable {
    /// Per stop, the lines not stopping there. An empty set means every line.
    public private(set) var byStation: [Int: Set<String>] = [:]

    public init() {}

    public init(notices: [ServiceNotice], at date: Date) {
        for notice in notices where notice.closesStops && notice.isActive(at: date) {
            for station in notice.stations {
                if notice.lines.isEmpty || byStation[station]?.isEmpty == true {
                    byStation[station] = []
                } else {
                    byStation[station, default: []].formUnion(notice.lines)
                }
            }
        }
    }

    public var stations: Set<Int> { Set(byStation.keys) }
    public var isEmpty: Bool { byStation.isEmpty }

    public func isClosed(station: Int, line: String) -> Bool {
        guard let lines = byStation[station] else { return false }
        return lines.isEmpty || lines.contains(line) || lines.contains(Line.feedNumber(line))
    }
}

/// A piece of a ride's way. A diverted piece runs past stops it doesn't serve, so its real streets are unknown.
public struct RideStretch: Sendable, Hashable {
    public var points: [Coordinate]
    public var isDiverted: Bool

    public init(points: [Coordinate], isDiverted: Bool) {
        self.points = points
        self.isDiverted = isDiverted
    }
}

extension RideLeg {
    /// The ride's way, split around closed stops: from the stop before the closed ones to the stop after them.
    public func stretches(closures: StopClosures) -> [RideStretch] {
        let way = path.count > 1 ? path : stops.map(\.platform.coordinate)
        let closed = stops.indices.filter { closures.isClosed(station: stops[$0].station.id, line: line.name) }
        guard !closed.isEmpty else { return [RideStretch(points: way, isDiverted: false)] }
        // Where each stop lies along the way, never going backwards.
        var places: [Int] = []
        var from = 0
        for stop in stops {
            let spot = stop.platform.coordinate
            let place = (from..<way.count).min { way[$0].distance(to: spot) < way[$1].distance(to: spot) } ?? from
            places.append(place)
            from = place
        }
        var result: [RideStretch] = []
        var done = 0
        var at = 0
        while at < closed.count {
            let first = closed[at]
            while at + 1 < closed.count, closed[at + 1] == closed[at] + 1 { at += 1 }
            let start = places[max(first - 1, 0)], end = places[min(closed[at] + 1, stops.count - 1)]
            if start > done { result.append(RideStretch(points: Array(way[done...start]), isDiverted: false)) }
            if end > start { result.append(RideStretch(points: Array(way[start...end]), isDiverted: true)) }
            done = max(done, end)
            at += 1
        }
        if done < way.count - 1 { result.append(RideStretch(points: Array(way[done...]), isDiverted: false)) }
        return result
    }

    public func isDiverted(closures: StopClosures) -> Bool {
        stops.contains { closures.isClosed(station: $0.station.id, line: line.name) }
    }
}

/// Reads EFA-BW's disruption list (`XML_ADDINFO_REQUEST`, rapidJSON) for Konstanz. The feed names lines and
/// stops as data; the words only decide whether a named stop is closed and which stops it suggests, and when
/// they don't say so the notice is only listed.
public enum EFANotices {
    /// About 16 KB. `filterOMC` is the municipality of Konstanz.
    public static let url = URL(string: "https://www.efa-bw.de/nvbw/XML_ADDINFO_REQUEST?"
        + "outputFormat=rapidJSON&filterPublished=1&filterOMC=8335043")!  // swiftlint:disable:this force_unwrapping
    private static let cityOperator = "SW-KN"

    private struct Feed: Decodable {
        struct Infos: Decodable { var current: [Info]? }
        var infos: Infos?
    }

    private struct Info: Decodable {
        struct Timestamps: Decodable {
            struct Range: Decodable { var from: String?, to: String? }
            var validity: [Range]?
        }

        struct Link: Decodable { var content: String? }

        struct Affected: Decodable {
            struct Operator: Decodable { var id: String? }
            struct InfoLine: Decodable {
                var number: String?
                var `operator`: Operator?
            }

            struct Stop: Decodable { var id: String? }
            var lines: [InfoLine]?
            var stops: [Stop]?
        }

        var id: String
        var version: Int?
        var type: String?
        var timestamps: Timestamps?
        var infoLinks: [Link]?
        var affected: Affected?
    }

    /// The notices that concern Konstanz's buses or stops. Throws on a broken answer, so the kept ones stay.
    public static func parse(_ data: Data, store: TimetableStore) throws -> [ServiceNotice] {
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard let infos = feed.infos else { throw URLError(.cannotParseResponse) }
        return (infos.current ?? []).compactMap { notice($0, store: store) }
    }

    private static func notice(_ info: Info, store: TimetableStore) -> ServiceNotice? {
        let cityLines = (info.affected?.lines ?? []).filter { $0.operator?.id == cityOperator }
        let stations = Array(Set((info.affected?.stops ?? []).compactMap { $0.id.flatMap(store.stationID(stopArea:)) }))
            .sorted()
        guard !cityLines.isEmpty || !stations.isEmpty,
              let text = info.infoLinks?.first?.content.map(plainText), !text.isEmpty else { return nil }
        let periods = (info.timestamps?.validity ?? []).compactMap { range -> ServiceNotice.Period? in
            guard let from = range.from.flatMap(date), let to = range.to.flatMap(date) else { return nil }
            return ServiceNotice.Period(from: from, to: to)
        }
        guard !periods.isEmpty else { return nil }
        let lines = Array(Set((info.affected?.lines ?? []).compactMap { $0.number?.replacingOccurrences(of: " ", with: "") }))
            .sorted { LineOrder.precedes($0, $1) }
        let closes = !stations.isEmpty && saysClosed(text)
        return ServiceNotice(id: info.id, version: info.version ?? 1, text: text, lines: lines, stations: stations,
                             closesStops: closes,
                             alternatives: closes ? alternatives(in: text, closed: stations, store: store) : [],
                             periods: periods)
    }

    // MARK: Words

    private static let closedPhrases = ["nicht angefahren", "nicht bedient", "nicht angedient", "nicht bedienen",
                                        "entfällt", "entfallen", "aufgehoben", "gesperrt"]
    /// Things at a stop that break without the buses stopping coming.
    private static let notAboutTheBus = ["aufzug", "fahrstuhl", "rolltreppe", "fahrkartenautomat", "ticketautomat"]

    static func saysClosed(_ text: String) -> Bool {
        let lower = text.lowercased()
        return closedPhrases.contains { lower.contains($0) } && !notAboutTheBus.contains { lower.contains($0) }
    }

    /// The stops the text sends people to ("Bitte nutzen Sie die Haltestelle Döbelestr. oder Gartenstraße"),
    /// else the nearest open ones.
    static func alternatives(in text: String, closed: [Int], store: TimetableStore) -> [Int] {
        let advice = fold(text)
        var found: [(position: String.Index, id: Int)] = []
        if let start = ["nutzen", "alternativ", "stattdessen", "ausweich", "ersatzhaltestelle"]
            .compactMap({ advice.range(of: $0)?.lowerBound }).min() {
            let part = advice[start...]
            for station in store.stations where !closed.contains(station.id) {
                let name = fold(station.shortName)
                var from = part.startIndex
                while let hit = part.range(of: name, range: from..<part.endIndex) {
                    let before = hit.lowerBound == part.startIndex ? " " : part[part.index(before: hit.lowerBound)]
                    let after = hit.upperBound == part.endIndex ? " " : part[hit.upperBound]
                    if !before.isLetter, !after.isLetter {
                        found.append((hit.lowerBound, station.id))
                        break
                    }
                    from = hit.upperBound
                }
            }
        }
        if !found.isEmpty { return found.sorted { $0.position < $1.position }.map(\.id) }
        let points = closed.compactMap { store.station(id: $0)?.coordinate }
        guard let first = points.first else { return [] }
        return store.stations(near: first, within: 800, limit: 2 + closed.count)
            .map(\.0.id).filter { !closed.contains($0) }.prefix(2).map { $0 }
    }

    /// Lower case without accents, with "Döbelestr." spelled out, to compare with stop names.
    private static func fold(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ß", with: "ss")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "str.", with: "strasse")
    }

    /// The feed's HTML as plain text.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<br\\s*/?>|</div>|</p>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, letter) in entities { text = text.replacingOccurrences(of: entity, with: letter) }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let entities = [
        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß",
        "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&bdquo;": "„",
        "&ldquo;": "“", "&ndash;": "–", "&mdash;": "—", "&euro;": "€", "&amp;": "&"
    ]

    private static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }
}
