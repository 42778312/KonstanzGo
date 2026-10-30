#if os(macOS)
import AVFoundation
import Foundation
import Speech
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

    /// Voice search keeps a recognizer with its model loaded (about 2 s to load); with it, the first words
    /// come back almost at once.
    @available(macOS 26, *)
    @Test("a prepared recognizer answers quickly")
    func preparedIsQuick() async throws {
        let module = try #require(await OfflineSpeech.transcriber())
        try await OfflineSpeech.install(module)
        let analyzer = SpeechAnalyzer(modules: [module])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
        try await analyzer.prepareToAnalyze(in: format)
        let audio = try AVAudioFile(forReading: spoken("Sternenplatz"))
        let clock = ContinuousClock()
        let start = clock.now
        let first = Task { () -> Duration? in
            for try await result in module.results where !result.text.characters.isEmpty { return clock.now - start }
            return nil
        }
        try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
        let delay = try #require(try await first.value)
        #expect(delay < .milliseconds(500), "first words after \(delay)")
    }
}
#endif
