#if DEBUG
import Foundation

/// The water-pipe closure as EFA-BW sent it on 5 Nov 2026, valid for years, for UI tests.
enum LiveSample {
    /// A new id on every launch, so Seeri announces it in each test.
    static let answer = Data(#"""
    {"infos":{"current":[{"type":"stopInfo","id":"SAMPLE","version":1,
    "timestamps":{"validity":[{"from":"2020-01-01T00:00:00Z","to":"2099-01-01T00:00:00Z"}]},
    "infoLinks":[{"content":"<div>Aufgrund eines Wasserrohrbruchs, k&ouml;nnen die Haltestellen \#
    Br&uuml;elstr. und Schulthai&szlig;str. nicht angefahren werden. Bitte \#
    nutzen Sie die Haltestelle D&ouml;belestr. oder Gartenstra&szlig;e.</div>"}],
    "affected":{"lines":[{"number":"1","operator":{"id":"SW-KN"}},{"number":"5","operator":{"id":"SW-KN"}},
    {"number":"9","operator":{"id":"SW-KN"}}],
    "stops":[{"id":"de:08335:11821"},{"id":"de:08335:11905"}]}}]}}
    """#.replacingOccurrences(of: "SAMPLE", with: UUID().uuidString).utf8)
}
#endif
