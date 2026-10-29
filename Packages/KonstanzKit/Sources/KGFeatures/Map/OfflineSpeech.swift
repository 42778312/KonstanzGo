import AVFoundation
import Foundation
import Speech

/// Apple's on-device dictation (iOS 26): German first, since Konstanz's stops and places have German names,
/// else the phone's language. The language model is downloaded once (that one time needs a connection);
/// after that recognition runs without internet and nothing leaves the iPhone.
@available(iOS 26, macOS 26, *)
enum OfflineSpeech {
    enum Failure: Error { case noLanguage }

    /// Dictation for short phrases ("Sternenplatz", "Universität"), with words as they come.
    static func transcriber(preferring locale: Locale = .current) async -> DictationTranscriber? {
        for wanted in [Locale(identifier: "de-DE"), locale] {
            if let supported = await DictationTranscriber.supportedLocale(equivalentTo: wanted) {
                return DictationTranscriber(locale: supported, preset: .progressiveShortDictation)
            }
        }
        return nil
    }

    static func isInstalled(_ module: DictationTranscriber) async -> Bool {
        await AssetInventory.status(forModules: [module]) == .installed
    }

    /// Downloads the language model if it isn't on the device yet.
    static func install(_ module: DictationTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    /// Stop and place names, so the recognizer prefers "Sternenplatz" over "Sternen Platz".
    static func context(hints: [String]) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints
        return context
    }

    /// The final words so far plus the ones still changing.
    struct Transcript: Sendable {
        private var settled = AttributedString()
        private(set) var text = ""

        mutating func add(_ result: DictationTranscriber.Result) {
            if result.isFinal {
                settled += result.text
                text = String(settled.characters)
            } else {
                text = String((settled + result.text).characters)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        }
    }

    /// Transcribes a recording (used by the tests with a spoken file).
    static func transcribe(file url: URL, hints: [String] = []) async throws -> String {
        guard let module = await transcriber() else { throw Failure.noLanguage }
        try await install(module)
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.setContext(context(hints: hints))
        let collect = Task {
            var transcript = Transcript()
            for try await result in module.results { transcript.add(result) }
            return transcript.text
        }
        try await analyzer.start(inputAudioFile: AVAudioFile(forReading: url), finishAfterFile: true)
        return try await collect.value
    }
}
