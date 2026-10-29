#if os(macOS)
import Foundation
import Testing
@testable import KGFeatures

/// The voice search's recognizer on spoken German stop and place names: the Mac's German voice says them
/// into a file, the on-device dictation (the same code the iPhone uses) writes them down.
@Suite("Offline speech", .serialized)
struct OfflineSpeechTests {
    private func spoken(_ words: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Anna", "-o", url.path, words]
        try say.run()
        say.waitUntilExit()
        return url
    }

    @available(macOS 26, *)
    @Test("hears stop and place names", arguments: ["Sternenplatz", "Bahnhof", "Universität", "Konzil"])
    func hearsNames(_ name: String) async throws {
        let text = try await OfflineSpeech.transcribe(file: spoken(name), hints: ["Sternenplatz", "Bodanplatz", "Konzil"])
        #expect(text.localizedCaseInsensitiveContains(name), "heard \"\(text)\"")
    }
}
#endif
