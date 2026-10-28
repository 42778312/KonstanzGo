import Foundation

/// How search compares text: lower case, ß = ss, accents and umlauts ignored ("Bäckerei" = "backerei"),
/// umlauts spelt out match too ("Muenster" = "Münster"), "str." = "straße". Same rules as the Android app.
public enum SearchText {
    /// Lower case, ß → ss, accents removed.
    public static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Folded words, with "ae"/"oe"/"ue" read as umlauts and "str" as "strasse".
    public static func tokens(_ text: String) -> [String] {
        let folded = fold(text)
            .replacingOccurrences(of: "ae", with: "a")
            .replacingOccurrences(of: "oe", with: "o")
            .replacingOccurrences(of: "ue", with: "u")
        return folded.split { !$0.isLetter && !$0.isNumber }.map { $0 == "str" ? "strasse" : String($0) }
    }

    /// Typos between what was typed and the start of a word (Damerau–Levenshtein against the word's first
    /// `typed.count` ± 1 letters): "bahnhfo" ≈ "bahnhof", "univrsitat" ≈ "universitat". Stops past `max`.
    public static func typoDistance(_ typed: String, _ word: String, max: Int) -> Int {
        typoDistance(Array(typed), Array(word), max: max)
    }

    static func typoDistance<Letter: Equatable>(_ typed: [Letter], _ word: [Letter], max: Int) -> Int {
        if abs(word.count - typed.count) > max && word.count < typed.count { return max + 1 }
        var best = max + 1
        for length in (typed.count - 1)...(typed.count + 1) where length >= 1 && length <= word.count {
            best = min(best, damerau(typed, Array(word[0..<length]), max: max))
        }
        return best
    }

    private static func damerau<Letter: Equatable>(_ lhs: [Letter], _ rhs: [Letter], max: Int) -> Int {
        let rows = lhs.count, columns = rhs.count
        guard rows > 0, columns > 0 else { return Swift.max(rows, columns) }
        if abs(rows - columns) > max { return max + 1 }
        var beforePrevious = [Int](repeating: 0, count: columns + 1)
        var previous = Array(0...columns)
        var current = [Int](repeating: 0, count: columns + 1)
        for row in 1...rows {
            current[0] = row
            var rowMinimum = row
            for column in 1...columns {
                let cost = lhs[row - 1] == rhs[column - 1] ? 0 : 1
                var value = min(previous[column] + 1, current[column - 1] + 1, previous[column - 1] + cost)
                if row > 1, column > 1, lhs[row - 1] == rhs[column - 2], lhs[row - 2] == rhs[column - 1] {
                    value = min(value, beforePrevious[column - 2] + 1)
                }
                current[column] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > max { return max + 1 }
            (beforePrevious, previous, current) = (previous, current, beforePrevious)
        }
        return previous[columns]
    }

    /// The characters of `name` that a typed word matched, for the bold part ("Uni" in "**Uni**versität").
    /// The first word of `name` that starts with the typed word, as far as it was typed; nil if none.
    public static func highlight(in name: String, typed: String) -> Range<Int>? {
        guard let query = tokens(typed).first else { return nil }
        let characters = Array(name)
        var index = 0
        while index < characters.count {
            guard characters[index].isLetter || characters[index].isNumber else { index += 1; continue }
            let start = index
            while index < characters.count, characters[index].isLetter || characters[index].isNumber { index += 1 }
            let word = String(characters[start..<index])
            guard let folded = tokens(word).first, folded.hasPrefix(query) else { continue }
            // Walk the original letters until their folded form covers what was typed.
            var covered = 0, end = start
            while end < index, covered < query.count {
                covered = tokens(String(characters[start...end])).first?.count ?? 0
                end += 1
            }
            return start..<end
        }
        return nil
    }
}

/// A folded word as UTF-8 bytes. Search compares these instead of `String`s: the same answers for the
/// folded text, many times faster over 29,000 entries.
typealias SearchWord = [UInt8]

extension Array where Element == UInt8 {
    func hasPrefix(_ prefix: [UInt8]) -> Bool {
        count >= prefix.count && self[0..<prefix.count].elementsEqual(prefix)
    }

    func containsRun(_ part: [UInt8]) -> Bool {
        guard !part.isEmpty, part.count <= count else { return part.isEmpty }
        let first = part[0]
        for start in 0...(count - part.count) where self[start] == first
            && self[start..<(start + part.count)].elementsEqual(part) {
            return true
        }
        return false
    }
}
