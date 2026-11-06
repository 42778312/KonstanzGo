import Foundation
import Testing
@testable import KGCore

@Suite("Search text")
struct SearchTextTests {
    @Test func foldsCaseUmlautsAndSharpS() {
        #expect(SearchText.fold("Bäckerei") == "backerei")
        #expect(SearchText.fold("Gießberg") == "giessberg")
        #expect(SearchText.fold("ÉCOLE") == "ecole")
    }

    @Test func spelledOutUmlautsAndStreetAbbreviation() {
        #expect(SearchText.tokens("Universitaet") == SearchText.tokens("Universität"))
        #expect(SearchText.tokens("Seestr. 21") == ["seestrasse", "21"] || SearchText.tokens("Seestr. 21") == ["seestr", "21"])
        #expect(SearchText.tokens("Bahnhof Str.") == ["bahnhof", "strasse"])
        #expect(SearchText.tokens("Hopp dä Bäsa, Beiz - Kafi") == ["hopp", "da", "basa", "beiz", "kafi"])
    }

    @Test func typoDistanceCountsSwapsAsOne() {
        #expect(SearchText.typoDistance("bahnhfo", "bahnhof", max: 1) == 1)
        #expect(SearchText.typoDistance("univrsitat", "universitat", max: 2) == 1)
        #expect(SearchText.typoDistance("konzil", "konzil", max: 1) == 0)
        #expect(SearchText.typoDistance("xyzabc", "bahnhof", max: 1) == 2)
    }

    @Test func highlightsWhatWasTyped() {
        // Design 08: "Uni" bold in "Universität".
        #expect(SearchText.highlight(in: "Universität", typed: "Uni") == 0..<3)
        #expect(SearchText.highlight(in: "Universität Konstanz", typed: "kon") == 12..<15)
        // Folded letters map back to the original ones: "gies" covers "Gieß" (ß = ss).
        #expect(SearchText.highlight(in: "Mensa Gießberg", typed: "giess") == 6..<10)
        #expect(SearchText.highlight(in: "Konzil", typed: "xyz") == nil)
    }
}

/// Against the real bundled index (29k entries) and stations.
@Suite("Place search")
struct PlaceSearchTests {
    static let store = try? TimetableStore(url: repoData.timetable)
    static let index: PlaceSearch? = store.flatMap { try? PlaceSearch(indexURL: repoData.searchIndex, store: $0) }

    var search: PlaceSearch { get throws { try #require(Self.index) } }

    @Test func loadsEverything() throws {
        #expect(try search.count == 28_992 + 142)
    }

    @Test func gzipReadsHeaderExtrasAndNames() throws {
        // "hello\n" packed by gzip with a 300-byte FEXTRA field and a file name (FNAME), built here by hand.
        let deflated: [UInt8] = [0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0xE7, 0x02, 0x00]
        var file: [UInt8] = [0x1F, 0x8B, 8, 0x04 | 0x08, 0, 0, 0, 0, 0, 3]
        file += [44, 1] + [UInt8](repeating: 7, count: 300)  // XLEN = 300 (little-endian), then the field
        file += Array("x.txt".utf8) + [0]
        file += deflated
        file += [0x20, 0x30, 0x3A, 0x36, 6, 0, 0, 0]  // CRC32, ISIZE = 6
        #expect(try Gzip.decompress(Data(file)) == Data("hello\n".utf8))
    }

    @Test func gzipRejectsOtherData() {
        #expect(throws: Gzip.Failure.self) { try Gzip.decompress(Data("plain text, not gzip at all".utf8)) }
    }

    @Test func uniFindsTheStopAndTheUniversityFirst() throws {
        // Design 08: typing "Uni" shows the stop "Universität" first, then the university, "Uni" in bold.
        let results = try search.search("Uni")
        #expect(results.first?.name == "Universität")
        #expect(results.first.map { if case .station = $0.target { true } else { false } } == true)
        #expect(results.prefix(3).contains { $0.name == "Universität Konstanz" })
        #expect(results.first?.match == 0..<3)
        // The design's "Universität · Haltestelle" is the real stop "Egg/Universität".
        #expect(try search.search("Egg Uni").first?.name == "Egg/Universität")
    }

    @Test func aStationBeatsTheStreetOfTheSameName() throws {
        // Before: indexed as "Konstanz Sternenplatz", the station lost to the street "Sternenplatz" (22 vs 41).
        let first = try #require(try search.search("Sternenplatz").first)
        guard case let .station(station, lines) = first.target else {
            Issue.record("first result is \(first.name), not the station")
            return
        }
        #expect(station.id == 99)
        #expect(lines.map(\.name).contains("9"))
    }

    @Test func germanAndEnglishCategoryWords() throws {
        #expect(try search.search("Apotheke").count >= 3)
        #expect(try search.search("pharmacy").count >= 3)
    }

    @Test func toleratesASmallTypo() throws {
        let results = try search.search("Bahnhfo")
        #expect(results.prefix(5).contains { $0.name.contains("Bahnhof") })
    }

    @Test func houseNumbersFindAddressesOrTheStreet() throws {
        let results = try search.search("Seestraße 21")
        #expect(results.first?.name.hasPrefix("Seestraße") == true)
    }

    @Test func addressesOnlyWithANumber() throws {
        let results = try search.search("Seestraße")
        #expect(!results.contains { if case let .place(place) = $0.target { place.kind == .address } else { false } })
    }

    @Test func emptyOrSymbolsFindNothing() throws {
        #expect(try search.search("").isEmpty)
        #expect(try search.search("  ,.- ").isEmpty)
    }

    @Test func germanCategoryIsKept() throws {
        let uni = try #require(try search.search("Universität Konstanz").first {
            if case let .place(place) = $0.target { place.id == "universitaet-konstanz" } else { false }
        })
        guard case let .place(place) = uni.target else { return }
        #expect(place.categoryGerman == "Universität")
        #expect(place.address == "Universitätsstraße 10")
    }

    @Test func typingIsFast() throws {
        let search = try search
        // The index loads in the background; `SpeedTests` times that wait. This is about typing.
        _ = search.count
        let start = Date()
        for prefix in ["U", "Un", "Uni", "Univ", "Unive", "Konz", "Bahnh", "Apoth", "Markts", "Seestr"] {
            _ = search.search(prefix)
        }
        let perKey = Date().timeIntervalSince(start) / 10
        // Release (swift test -c release): 2-9 ms per key on a Mac. Debug builds are unoptimised and the
        // other tests run at the same time, so the debug bound only catches a tenfold slowdown.
        #if DEBUG
        let budget = 0.25
        #else
        let budget = 0.025
        #endif
        #expect(perKey < budget, "\(Int(perKey * 1000)) ms per keystroke")
    }
}

@Suite("Reverse lookup")
struct ReverseLookupTests {
    @Test func namesTheStreetAndNearestStation() throws {
        let store = try TimetableStore(url: repoData.timetable)
        let lookup = ReverseLookup(walk: WalkRouter(graph: try WalkGraph.read(from: repoData.walkGraph)), store: store)
        let sternenplatz = try #require(store.station(id: 99))
        let here = lookup.whereabouts(at: sternenplatz.coordinate, townFrom: PlaceSearchTests.index)
        #expect(here.street != nil)
        #expect(here.nearestStation?.id == 99)
        #expect(here.walkMinutes == 1)
        #expect(here.town == "Konstanz")
    }

    @Test func nothingOnTheLake() throws {
        let store = try TimetableStore(url: repoData.timetable)
        let lookup = ReverseLookup(walk: WalkRouter(graph: try WalkGraph.read(from: repoData.walkGraph)), store: store)
        let lake = Coordinate(latitude: 47.64, longitude: 9.25)
        #expect(lookup.street(near: lake) == nil)
    }
}
