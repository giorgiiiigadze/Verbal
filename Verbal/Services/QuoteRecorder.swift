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
        case unavailable
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
    var hasContent: Bool { !transcript.isEmpty }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

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
        guard state == .idle || state == .unavailable else { return }
        state = .preparing
        errorMessage = nil

        guard await requestPermissions() else {
            errorMessage = "Microphone and speech permission are required."
            state = .unavailable
            return
        }

        do {
            let transcriber = SpeechTranscriber(
                locale: Locale.current,
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

            state = .recording
            startTimer()
        } catch {
            fail(error)
        }
    }

    // MARK: - Stop

    func stop() async {
        timerTask?.cancel()
        timerTask = nil

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

        if state != .unavailable { state = .idle }
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

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
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
        state = .idle
    }

    // MARK: - Model + permissions

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
