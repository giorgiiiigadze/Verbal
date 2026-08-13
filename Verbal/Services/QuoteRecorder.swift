//
//  QuoteRecorder.swift
//  Verbal
//
//  On-device speech-to-text using Apple's SpeechAnalyzer / SpeechTranscriber
//  (iOS 26+). Audio never leaves the device — only the transcript text is used.
//

import Foundation
import Speech
import AVFoundation
@preconcurrency import AVFAudio

@MainActor
@Observable
final class QuoteRecorder {
    enum State {
        case idle
        case preparing
        case recording
        /// Something took the microphone away — a call, Siri, the app going to
        /// the background. Distinct from `.idle` because the words already said
        /// are still here and the user has not finished: nothing may be
        /// generated from this state until they say so.
        case interrupted
        case unavailable
    }

    /// What recording may do right now, readable without triggering a prompt —
    /// so the app can explain itself before iOS spends its one-shot dialog.
    enum Access {
        /// Both permissions granted; `start()` will just work.
        case ready
        /// Never asked. The next `start()` is what raises the system dialogs.
        case notAsked
        /// Denied or restricted. iOS will not ask again; only Settings undoes it.
        case blocked
    }

    /// Current authorization, read (not requested) from both systems the
    /// recorder needs: speech recognition and the microphone itself.
    static var access: Access {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission
        if speech == .denied || speech == .restricted || microphone == .denied {
            return .blocked
        }
        if speech == .authorized && microphone == .granted {
            return .ready
        }
        return .notAsked
    }

    private(set) var state: State = .idle
    private(set) var errorMessage: String?

    /// Text that has been finalized by the recognizer.
    private(set) var finalizedText = ""
    /// The latest volatile (in-progress) hypothesis for the current phrase.
    private(set) var volatileText = ""

    /// Seconds elapsed while recording (drives the timer indicator).
    private(set) var elapsed: TimeInterval = 0
    private var timerTask: Task<Void, Never>?

    /// Normalized live microphone level (0...1) for the voice meter.
    private(set) var audioLevel: Float = 0
    private var levelContinuation: AsyncStream<Float>.Continuation?

    /// Full transcript for display / sending to the extraction function.
    var transcript: String {
        (finalizedText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isRecording: Bool { state == .recording }
    var isPaused: Bool { state == .interrupted }
    /// Recording or paused — a session the user is in the middle of, either way.
    var isSessionActive: Bool { isRecording || isPaused }
    var hasContent: Bool { !transcript.isEmpty }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?

    /// Bumped by anything that ends a session. `start()` carries a copy across
    /// its awaits and abandons the attempt if it has moved on, because setting
    /// up a recording takes several suspension points — permission dialogs, a
    /// model download on first run — and a call arriving in one of them would
    /// otherwise be undone by the setup finishing on top of it.
    private var sessionToken = 0

    private let audioEngine = AVAudioEngine()

    // MARK: - Public control

    func toggle() async {
        if isRecording {
            await stop()
        } else {
            await start()
        }
    }

    func reset() {
        finalizedText = ""
        volatileText = ""
        elapsed = 0
        errorMessage = nil
    }

    /// Seed the transcript before resuming, so hand-edits made while paused are kept
    /// and new speech continues from them.
    func seed(_ text: String) {
        finalizedText = text
        volatileText = ""
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.state == .recording else { continue }
                self.elapsed += 1
            }
        }
    }

    var elapsedText: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Start

    func start() async {
        // `.interrupted` resumes through here: the text already said is still in
        // `finalizedText`, so the separator below and the running `elapsed` make
        // it a continuation rather than a second recording.
        guard state == .idle || state == .interrupted || state == .unavailable else { return }
        state = .preparing
        errorMessage = nil

        sessionToken += 1
        let token = sessionToken

        guard await requestPermissions() else {
            errorMessage = "Microphone and speech permission are required."
            state = .unavailable
            return
        }

        // Resuming: add a separator so new speech doesn't run into the prior text.
        if !finalizedText.isEmpty, !finalizedText.hasSuffix(" ") {
            finalizedText += " "
        }

        do {
            guard let locale = await Self.transcriptionLocale() else {
                errorMessage = "Speech recognition isn't available in this language yet."
                state = .unavailable
                return
            }

            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            self.transcriber = transcriber

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            try await ensureModel(for: transcriber)

            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
            )

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation

            let (levelStream, levelCont) = AsyncStream<Float>.makeStream()
            levelContinuation = levelCont
            Task { [weak self] in
                for await level in levelStream {
                    self?.audioLevel = level
                }
            }

            resultsTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        self.handle(text: text, isFinal: result.isFinal)
                    }
                } catch {
                    self.fail(error)
                }
            }

            try await analyzer.start(inputSequence: stream)
            try startAudio(convertingTo: analyzerFormat)

            // Something ended the session while the lines above were awaiting —
            // a call, or the app going to the background. That teardown already
            // finished the input stream, so carrying on would set `.recording`
            // over a microphone feeding nowhere: a running timer, no paused
            // notice, and not a word captured.
            guard token == sessionToken else {
                await teardown()
                return
            }

            state = .recording
            startTimer()
            observeInterruptions()
        } catch {
            fail(error)
        }
    }

    // MARK: - Stop

    func stop() async {
        await teardown()
        if state != .unavailable { state = .idle }
    }

    /// Give up the microphone without ending the session.
    ///
    /// Deliberately not `stop()`: the recording view generates a quote whenever
    /// recording stops with something in it, so routing a phone call through
    /// that path would extract a half-finished transcript on the user's behalf.
    /// This keeps the words, gives back the audio session, and waits.
    func interrupt() async {
        guard state == .recording || state == .preparing else { return }
        await teardown()
        state = .interrupted
    }

    /// Everything both endings share. Folding the volatile hypothesis into the
    /// finalized text here is what keeps the half-spoken sentence someone was in
    /// the middle of when the phone rang.
    private func teardown() async {
        // Anything in flight in `start()` belongs to a session that is over.
        sessionToken += 1

        timerTask?.cancel()
        timerTask = nil

        interruptionTask?.cancel()
        interruptionTask = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        inputContinuation?.finish()
        inputContinuation = nil

        levelContinuation?.finish()
        levelContinuation = nil
        audioLevel = 0

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask = nil
        analyzer = nil
        transcriber = nil

        // Fold any remaining volatile text into the finalized transcript.
        if !volatileText.isEmpty {
            finalizedText += volatileText
            volatileText = ""
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Watches for the system taking the microphone — an incoming call, Siri,
    /// another app claiming it.
    ///
    /// `.ended` is ignored on purpose, even when iOS offers `.shouldResume`.
    /// A call ends with the phone against the user's ear, and starting to listen
    /// again unannounced would record whatever they said next. Resuming is a tap
    /// on the mic, which is where they'd look for it anyway.
    private func observeInterruptions() {
        interruptionTask?.cancel()
        interruptionTask = Task { [weak self] in
            let interruptions = NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            )
            for await notification in interruptions {
                guard !Task.isCancelled else { return }
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .began else {
                    continue
                }
                await self?.interrupt()
            }
        }
    }

    // MARK: - Audio capture

    private func startAudio(convertingTo analyzerFormat: AVAudioFormat?) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let converter: AVAudioConverter?
        if let analyzerFormat, analyzerFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        } else {
            converter = nil
        }

        let continuation = inputContinuation
        let levelCont = levelContinuation

        // Smaller buffer → audio reaches the recognizer more often → lower latency.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            levelCont?.yield(Self.level(from: buffer))
            guard let continuation else { return }
            if let converter, let analyzerFormat,
               let converted = Self.convert(buffer, using: converter, to: analyzerFormat) {
                continuation.yield(AnalyzerInput(buffer: converted))
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Normalized RMS level (0...1) of a buffer, for the voice meter.
    private nonisolated static func level(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let samples = channel[0]
        var sum: Float = 0
        for i in 0..<frames {
            let s = samples[i]
            sum += s * s
        }
        let rms = sqrt(sum / Float(frames))
        // Map roughly -50 dB…0 dB to 0…1.
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 50) / 50))
    }

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var error: NSError?
        var supplied = false
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    // MARK: - Results / errors

    private func handle(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        // Never erase a pause. If the session was interrupted while this attempt
        // was in flight, `.interrupted` is the truthful state — dropping to
        // `.idle` would take the paused notice off screen and leave the failure
        // looking like an ordinary finished transcript.
        if state != .interrupted { state = .idle }
    }

    // MARK: - Model + permissions

    /// The locale to transcribe in — one the model actually exists in.
    ///
    /// `Locale.current` used to go straight to `SpeechTranscriber`, which is the
    /// phone's setting rather than a promise that Apple built a model for it. A
    /// tradesperson whose phone is set to a language with no speech model got a
    /// failed recording where the words were fine; the model for them was never
    /// on the device.
    ///
    /// Region matters too, and quietly: en_US and en_GB are different models,
    /// and asking the American one to hear a British accent is a mis-hearing per
    /// sentence rather than an outright failure — the worse of the two, because
    /// nothing on screen says it happened.
    ///
    /// So: the exact locale, then the same language spoken elsewhere, then
    /// English, which is what the app itself is written in and the language its
    /// prompts read. Nil only when even that is missing, which is a state the
    /// caller has to tell the user about rather than push a microphone at.
    private static func transcriptionLocale() async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        let device = Locale.current

        func best(_ code: Locale.LanguageCode) -> Locale? {
            let candidates = supported.filter { $0.language.languageCode == code }
            guard !candidates.isEmpty else { return nil }
            // The phone's own region reads its owner's accent best.
            if let exact = candidates.first(where: { $0.region == device.region }) {
                return exact
            }
            // Falling back across regions is already a compromise; en_US is the
            // most widely trained of them and a stable choice, rather than
            // whichever locale Apple happened to list first.
            if let widest = candidates.first(where: { $0.region == Locale.Region("US") }) {
                return widest
            }
            return candidates.first
        }

        guard let language = device.language.languageCode else { return best(.english) }
        return best(language) ?? best(.english)
    }

    private func ensureModel(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private func requestPermissions() async -> Bool {
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
