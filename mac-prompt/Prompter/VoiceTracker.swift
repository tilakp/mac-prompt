//
//  VoiceTracker.swift
//  mac-prompt
//
//  Scoped version of "voice tracking": this does NOT attempt word-level alignment
//  (scrubbing the scroll position to the exact word being spoken), which is a much
//  harder, research-grade problem. Instead it runs live on-device speech recognition,
//  measures the presenter's actual words-per-minute since the current recognition
//  session started, and smoothly nudges TeleprompterEngine.speedMultiplier toward
//  that measured rate. It also reports mic RMS level for the control bar's waveform.
//  `@Observable`, so the ~20Hz `micLevel` updates re-render only the control bar's
//  waveform, not the whole Prompter view.

import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class VoiceTracker {
    private(set) var isListening = false
    private(set) var micLevel: Double = 0
    private(set) var measuredWPM: Double?

    var sensitivity: VoiceTrackingSensitivity = .balanced

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    /// Kept for the whole session: the recognition task must not outlive its recognizer.
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    /// Incremented on each `start()`, so callbacks from an older recognition task are ignored.
    @ObservationIgnored private var sessionID = 0

    /// Touched only from the audio tap's render-thread callback below (never from
    /// MainActor code), which AVAudioEngine always invokes serially on the same
    /// thread — safe without extra synchronization. Throttles how often the tap
    /// hops to MainActor to publish `micLevel`: the callback fires ~40-50x/sec for
    /// the whole session (30-60+ min), but the control bar only animates 4 bars, so
    /// there's no UX benefit to updating faster than ~20Hz — just actor-hop overhead.
    @ObservationIgnored nonisolated(unsafe) private var lastLevelUpdate = Date.distantPast
    @ObservationIgnored private var sessionStartDate: Date?

    static func requestPermissions() async -> Bool {
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        return micGranted && speechGranted
    }

    func start(engine: TeleprompterEngine) {
        guard !isListening else { return }
        // The user's own language first; nil means it is not supported, so fall back to en-US.
        let recognizer = self.recognizer ?? SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.recognizer = recognizer
        guard let recognizer, recognizer.isAvailable else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // With no input device (e.g. a Mac mini with no mic) the format has a zero
        // sample rate, and installTap raises an Objective-C exception that crashes the app.
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        sessionStartDate = .now

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let self else { return }
            let now = Date.now
            guard now.timeIntervalSince(self.lastLevelUpdate) >= 0.05 else { return }
            self.lastLevelUpdate = now
            let level = VoiceTracker.rmsLevel(of: buffer)
            Task { @MainActor [weak self] in self?.micLevel = level }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            return
        }
        isListening = true
        sessionID += 1
        let session = sessionID

        task = recognizer.recognitionTask(with: request) { [weak self, weak engine] result, error in
            Task { @MainActor [weak self, weak engine] in
                // A cancelled task (from stop() or restart()) still calls this handler with
                // an error. Without this check, that late callback restarts the new session,
                // which cancels it in turn, and so on in a loop.
                guard let self, let engine, session == self.sessionID else { return }
                if let result {
                    self.handle(result: result, engine: engine)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.restart(engine: engine)
                }
            }
        }
    }

    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        sessionStartDate = nil
        isListening = false
        micLevel = 0
        measuredWPM = nil
    }

    /// Live speech recognition sessions time out after roughly a minute; transparently
    /// start a fresh one so tracking keeps running through a long read.
    private func restart(engine: TeleprompterEngine) {
        guard isListening else { return }
        stop()
        start(engine: engine)
    }

    private func handle(result: SFSpeechRecognitionResult, engine: TeleprompterEngine) {
        guard let sessionStartDate else { return }
        let elapsed = Date.now.timeIntervalSince(sessionStartDate)
        guard elapsed > 2 else { return }

        let wordCount = result.bestTranscription.segments.count
        let wpm = Double(wordCount) / elapsed * 60
        measuredWPM = wpm

        let targetMultiplier = wpm / Double(max(engine.baseWPM, 1))
        let clamped = min(max(targetMultiplier, TeleprompterEngine.speedMultiplierRange.lowerBound), TeleprompterEngine.speedMultiplierRange.upperBound)
        engine.speedMultiplier += (clamped - engine.speedMultiplier) * sensitivity.dampingFactor
    }

    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(frameLength))
        return min(Double(rms) * 12, 1)
    }
}
