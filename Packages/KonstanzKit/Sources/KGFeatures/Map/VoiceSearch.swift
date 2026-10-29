import Foundation
import Observation
#if os(iOS)
import AVFoundation
import Speech
#endif

/// Voice search without internet: listens with the microphone and writes down where the user wants to go,
/// on the iPhone itself. On iOS 26 Apple's on-device dictation (``OfflineSpeech``), German first and primed
/// with the stop and place names; its model is downloaded once. Older iOS uses the classic recognizer, forced
/// on-device. Stops by itself after a short pause.
@MainActor
@Observable
final class VoiceSearch {
    enum State: Equatable {
        case idle
        /// Downloading the language model, the first time only.
        case preparing
        case listening
        /// Microphone or speech recognition not allowed in iOS settings.
        case denied
        /// No offline recognition for the language on this iPhone.
        case unavailable
        /// The model isn't on the iPhone yet and couldn't be downloaded (no connection).
        case needsDownload
    }

    private(set) var state = State.idle
    /// What was understood so far.
    private(set) var text = ""
    /// Names the recognizer should expect (the stops).
    var hints: [String] = []

    var isListening: Bool { state == .listening }

    #if os(iOS)
    private let engine = AVAudioEngine()
    private var silence: Task<Void, Never>?
    // iOS 26: the analyzer's input and the task reading its results.
    @ObservationIgnored private var endInput: (() -> Void)?
    @ObservationIgnored private var finishing: (() async -> Void)?
    @ObservationIgnored private var reading: Task<Void, Never>?
    // Before iOS 26.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    #endif

    func toggle() {
        if isListening || state == .preparing { stop() } else { Task { await start() } }
    }

    func start() async {
        #if os(iOS)
        guard state != .listening, state != .preparing else { return }
        text = ""
        if #available(iOS 26, *) {
            guard await AVAudioApplication.requestRecordPermission() else { return state = .denied }
            await startAnalyzer()
        } else {
            guard await Self.authorize() else { return state = .denied }
            startClassic()
        }
        #else
        state = .unavailable
        #endif
    }

    func stop() {
        #if os(iOS)
        silence?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        endInput?()
        endInput = nil
        if let finishing {
            self.finishing = nil
            // Let the analyzer settle the last words, then stop reading.
            Task { await finishing() }
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        if state == .listening || state == .preparing { state = .idle }
    }

    #if os(iOS)
    // MARK: iOS 26: on-device dictation

    @available(iOS 26, *)
    private func startAnalyzer() async {
        guard let module = await OfflineSpeech.transcriber() else { return state = .unavailable }
        if !(await OfflineSpeech.isInstalled(module)) {
            state = .preparing
            do { try await OfflineSpeech.install(module) } catch { return state = .needsDownload }
            guard state == .preparing else { return }  // cancelled meanwhile
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        do {
            try await analyzer.setContext(OfflineSpeech.context(hints: hints))
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                return state = .unavailable
            }
            try startMicrophone()
            let microphone = engine.inputNode.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: microphone, to: format) else { return fail() }
            let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: microphone,
                                        block: Self.feed(converter: converter, format: format, into: input))
            engine.prepare()
            try engine.start()
            try await analyzer.start(inputSequence: stream)
            endInput = { input.finish() }
        } catch {
            return fail()
        }
        reading = Task { [weak self] in
            var transcript = OfflineSpeech.Transcript()
            do {
                for try await result in module.results {
                    transcript.add(result)
                    self?.heard(transcript.text, done: false)
                }
            } catch {}
        }
        finishing = { [reading] in
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            await reading?.value
        }
        state = .listening
        waitForPause(first: true)
    }

    /// The microphone's audio, converted to what the analyzer wants, on the audio thread.
    @available(iOS 26, *)
    private nonisolated static func feed(converter: AVAudioConverter, format: AVAudioFormat,
                                         into input: AsyncStream<AnalyzerInput>.Continuation) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let ratio = format.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var given = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if given {
                    status.pointee = .noDataNow
                    return nil
                }
                given = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 { input.yield(AnalyzerInput(buffer: converted)) }
        }
    }

    // MARK: Before iOS 26: the classic recognizer, on-device only

    private func startClassic() {
        let recognizer = [Locale(identifier: "de-DE"), Locale.current].lazy
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.supportsOnDeviceRecognition }
        guard let recognizer else { return state = .unavailable }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .search
        request.contextualStrings = Array(hints.prefix(100))
        do {
            try startMicrophone()
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                             block: Self.feed(request))
            engine.prepare()
            try engine.start()
        } catch {
            return fail()
        }
        self.request = request
        state = .listening
        task = recognizer.recognitionTask(with: request, resultHandler: Self.results { [weak self] words, done in
            Task { @MainActor in self?.heard(words, done: done) }
        })
        waitForPause(first: true)
    }

    /// The microphone's audio into the recognizer, on the audio thread.
    private nonisolated static func feed(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// The recognizer calls back on its own queue, so the handler must not belong to the main actor.
    private nonisolated static func results(
        _ forward: @escaping @Sendable (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            forward(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    /// Asks for speech recognition and the microphone. iOS answers on a background queue, hence nonisolated.
    private nonisolated static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: Shared

    private func startMicrophone() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        engine.inputNode.removeTap(onBus: 0)
    }

    private func fail() {
        stop()
        state = .unavailable
    }

    private func heard(_ words: String?, done: Bool) {
        if let words, !words.isEmpty { text = words }
        guard isListening else { return }
        if done { stop() } else { waitForPause(first: false) }
    }

    /// Stops 1.5 s after the last word, or after 6 s if nothing was said.
    private func waitForPause(first: Bool) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(first ? 6 : 1.5))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
    #endif
}
