import Foundation
import Synchronization

/// Offline search over everything in Konstanz: places, streets, addresses, districts, towns
/// (`places.tsvz`) and the bus stations. Matches word beginnings as you type, several words in any order,
/// small typos, German and English category words ("Apotheke", "pharmacy") and house numbers; ranks by
/// how well it matches, how important the place is and how near it is. Same scoring as the Android app.
public final class PlaceSearch: Sendable {
    /// Where results are ranked from when the user's location is unknown: Konstanz's old town.
    public static let konstanzCentre = Coordinate(latitude: 47.6603, longitude: 9.1758)

    private let entries: [Entry]
    private let store: TimetableStore

    struct Entry: Sendable {
        var target: SearchEntryTarget
        /// "p:<slug>" or "s:<station id>"; tells entries with the same name apart.
        var id: String
        var name: String
        var group: String
        /// Importance 0…100.
        var rank: Int
        var coordinate: Coordinate
        var tokens: [SearchWord]
        var compact: SearchWord
        var keywords: [SearchWord]
    }

    public init(indexURL: URL, store: TimetableStore) throws {
        self.store = store
        let text = String(bytes: try Gzip.decompress(Data(contentsOf: indexURL)), encoding: .utf8) ?? ""
        var entries: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let entry = Self.entry(line) { entries.append(entry) }
        }
        // Bus stations rank together with places (Android: rank 45, group "Stop"), by the short name people
        // use and the design shows ("Sternenplatz", not "Konstanz Sternenplatz").
        for station in store.stations {
            entries.append(Self.makeEntry(target: .station(station), name: station.shortName, group: "Stop", rank: 45,
                                          coordinate: station.coordinate,
                                          keywords: "\(station.name) haltestelle bushaltestelle stop"))
        }
        self.entries = entries
    }

    public var count: Int { entries.count }

    /// A place by its slug (recent searches and favourites store only the id).
    public func place(id: String) -> Place? {
        for entry in entries {
            if case let .place(place) = entry.target, place.id == id { return place }
        }
        return nil
    }

    /// For reverse lookup (same module).
    var entriesForLookup: [Entry] { entries }

    /// Best matches for what was typed, ranked from `near` (the user's position, or the centre).
    public func search(_ query: String, near: Coordinate = konstanzCentre, limit: Int = 30) -> [SearchResult] {
        let words = SearchText.tokens(query).map { SearchWord($0.utf8) }
        guard !words.isEmpty else { return [] }
        let withNumber = words.contains { $0.contains { (48...57).contains($0) } }

        func run(_ words: [SearchWord], fuzzy: Bool, addresses: Bool) -> [(Entry, Double)] {
            let whole = SearchWord(words.joined())
            // Entries are scored independently, so the work is spread over the CPU cores in chunks.
            let chunks = 8, size = (entries.count + chunks - 1) / chunks
            let matches = Mutex<[(Entry, Double)]>([])
            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                var found: [(Entry, Double)] = []
                for entry in entries[min(chunk * size, entries.count)..<min((chunk + 1) * size, entries.count)]
                where entry.group != "Address" || addresses {  // house addresses only when a number is typed
                    if let score = score(entry, words, whole: whole, fuzzy: fuzzy, from: near) {
                        found.append((entry, score))
                    }
                }
                matches.withLock { $0 += found }
            }
            // Ties broken by id, so the order does not depend on which core finished first.
            return Array(matches.withLock { $0 }.sorted { ($0.1, $1.0.id) > ($1.1, $0.0.id) }.prefix(limit))
        }

        var found = run(words, fuzzy: false, addresses: withNumber)
        // A house number that is not mapped ("Schottenstraße 12"): the street itself, before guessing at typos.
        if withNumber, found.count < 6 {
            let plain = words.filter { !$0.contains { (48...57).contains($0) } }
            if !plain.isEmpty {
                let ids = Set(found.map(\.0.id))
                found += run(plain, fuzzy: false, addresses: false).filter { !ids.contains($0.0.id) }
            }
        }
        if found.count < 6 {
            let ids = Set(found.map(\.0.id))
            found += run(words, fuzzy: true, addresses: withNumber).filter { !ids.contains($0.0.id) }
        }
        return found.prefix(limit).map { entry, score in result(entry, score: score, typed: query) }
    }

    // MARK: Scoring

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// nil when a typed word matches nothing; in the fuzzy pass also when no typo was needed.
    private func score(_ entry: Entry, _ words: [SearchWord], whole: SearchWord, fuzzy: Bool,
                       from point: Coordinate) -> Double? {
        var total = 0.0, nameHits = 0, usedTypo = false
        for word in words {
            var best = 0.0, bestIsName = false, bestIsTypo = false
            for token in entry.tokens {
                let value: Double
                if token == word {
                    value = 10
                } else if token.hasPrefix(word) {
                    value = 7 + 2 * Double(word.count) / Double(token.count)
                } else if word.count >= 3, token.containsRun(word) {
                    value = 4
                } else {
                    value = 0
                }
                if value > best { best = value; bestIsName = true; bestIsTypo = false }
            }
            if best == 0, word.count >= 3, entry.compact.containsRun(word) { best = 3.5; bestIsName = true }
            if best < 6 {
                for keyword in entry.keywords {
                    let value = keyword == word ? 6.5 : (word.count >= 3 && keyword.hasPrefix(word) ? 5 : 0)
                    if value > best { best = value; bestIsName = false; bestIsTypo = false }
                }
            }
            if best == 0, fuzzy, word.count >= 4, !word.contains(where: { (48...57).contains($0) }) {
                let allowed = word.count >= 7 ? 2 : 1
                for token in entry.tokens {
                    let distance = SearchText.typoDistance(word, token, max: allowed)
                    if distance <= allowed, 6.5 - 1.5 * Double(distance) > best {
                        best = 6.5 - 1.5 * Double(distance); bestIsName = true; bestIsTypo = true
                    }
                }
                if best == 0 {
                    for keyword in entry.keywords where keyword.count >= 4
                        && SearchText.typoDistance(word, keyword, max: 1) <= 1 {
                        best = 1.5; bestIsName = false; bestIsTypo = true
                    }
                }
            }
            if best == 0 { return nil }
            total += best
            if bestIsName { nameHits += 1 }
            if bestIsTypo { usedTypo = true }
        }
        if fuzzy, !usedTypo { return nil }  // the strict pass found it already

        // The whole name typed from its start ("bahnhofpl" → Bahnhofplatz) beats words found anywhere.
        if entry.compact.hasPrefix(whole) { total += 12 }
        if entry.compact == whole { total += 8 }
        if nameHits == words.count, entry.tokens.count == words.count { total += 3 }
        let byCategory = nameHits == 0 && !usedTypo
        total += Double(entry.rank) / 10
        let metres = point.distance(to: entry.coordinate)
        total += (byCategory ? 14 : 7) * exp(-metres / (byCategory ? 1_200 : 2_500))
        switch entry.group {
        case "Stop": total += 2.5
        case "Town": total += 3
        case "District": total += 1.5
        case "Address": total += 4
        default: break
        }
        return total
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    private func result(_ entry: Entry, score: Double, typed: String) -> SearchResult {
        let target: SearchResult.Target
        switch entry.target {
        case let .place(place): target = .place(place)
        case let .station(station): target = .station(station, lines: (try? store.lines(at: station.id)) ?? [])
        }
        return SearchResult(target: target, match: SearchText.highlight(in: entry.name, typed: typed), score: score)
    }

    // MARK: Reading

    /// One line of places.tsvz: id, name, group, category, area, lat, lon, rank, keywords, address, category_de.
    private static func entry(_ line: Substring) -> Entry? {
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 11, let lat = Double(columns[5]), let lon = Double(columns[6]) else { return nil }
        let coordinate = Coordinate(latitude: lat, longitude: lon)
        let place = Place(id: columns[0], name: columns[1], kind: PlaceKind(rawValue: columns[2]) ?? .service,
                          category: columns[3], categoryGerman: columns[10], area: columns[4],
                          address: columns[9].isEmpty ? nil : columns[9], coordinate: coordinate)
        return makeEntry(target: .place(place), name: columns[1], group: columns[2], rank: Int(columns[7]) ?? 0,
                         coordinate: coordinate, keywords: "\(columns[3]) \(columns[10]) \(columns[8])")
    }

    // swiftlint:disable:next function_parameter_count
    private static func makeEntry(target: SearchEntryTarget, name: String, group: String, rank: Int,
                                  coordinate: Coordinate, keywords: String) -> Entry {
        let tokens = SearchText.tokens(name)
        var seen = Set<String>()
        let keywordTokens = SearchText.tokens(keywords).filter { seen.insert($0).inserted }.map { SearchWord($0.utf8) }
        let id: String
        switch target {
        case let .place(place): id = "p:\(place.id)"
        case let .station(station): id = "s:\(station.id)"
        }
        return Entry(target: target, id: id, name: name, group: group, rank: rank, coordinate: coordinate,
                     tokens: tokens.map { SearchWord($0.utf8) }, compact: SearchWord(tokens.joined().utf8),
                     keywords: keywordTokens)
    }
}

/// What a search entry stands for.
enum SearchEntryTarget: Sendable {
    case place(Place)
    case station(Station)
}
