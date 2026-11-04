//
//  VoiceTracker.swift
//  mac-prompt
//
//  Scoped version of "voice tracking": this does NOT attempt word-level alignment
//  (scrubbing the scroll position to the exact word being spoken), which is a much
//  harder, research-grade problem. Instead it runs live on-device speech recognition,
//  measures the presenter's words-per-minute over the last 10 seconds, and smoothly
//  nudges TeleprompterEngine.speedMultiplier toward that measured rate. It also reports mic RMS level for the control bar's waveform.
//  `@Observable`, so the ~20Hz `micLevel` updates re-render only the control bar's
//  waveform, not the whole Prompter view.

import AVFoundation
import Observation
@preconcurrency import Speech

@MainActor
@Observable
final class VoiceTracker {
    private(set) var isListening = false
    private(set) var micLevel: Double = 0
    private(set) var measuredWPM: Double?
    /// True when tracking stopped after too many quick failures. The control bar then
    /// offers "Retry" (`retry(engine:)`).
    private(set) var didFail = false

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
    /// (time, words recognized so far) for each result in the current session, kept
    /// back to the WPM window. See `windowedWPM(samples:)`.
    @ObservationIgnored private var wpmSamples: [(Date, Int)] = []
    @ObservationIgnored private var lastAdjustDate: Date?
    /// Sessions in a row that ended within 2 seconds. Some errors (no on-device model,
    /// Dictation off, recognizer busy) occur again at once on each new session.
    @ObservationIgnored private var quickFailures = 0

    static let wpmWindow: TimeInterval = 10
    private static let maxQuickFailures = 5

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
        let startDate = Date.now
        sessionStartDate = startDate
        // Silence before the first word counts, but only inside the WPM window.
        wpmSamples = [(startDate, 0)]
        lastAdjustDate = nil

        inputNode.removeTap(onBus: 0)
        // `@Sendable`: this runs on the audio render thread. Without it the closure is
        // inferred to be main-actor isolated, which stops the app in Swift 6 mode.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
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

        task = recognizer.recognitionTask(with: request) { @Sendable [weak self, weak engine] result, error in
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
        teardown()
        // Cancels a restart that is waiting (see `restart`) and ignores late callbacks.
        sessionID += 1
        quickFailures = 0
        didFail = false
    }

    /// Starts again after `didFail`.
    func retry(engine: TeleprompterEngine) {
        stop()
        start(engine: engine)
    }

    private func teardown() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        sessionStartDate = nil
        wpmSamples = []
        lastAdjustDate = nil
        isListening = false
        micLevel = 0
        measuredWPM = nil
    }

    /// Live speech recognition sessions time out after roughly a minute; transparently
    /// start a fresh one so tracking keeps running through a long read.
    /// A session that fails quickly is restarted after a growing delay, and after
    /// `maxQuickFailures` in a row tracking stops (the indicator then shows "Off").
    /// Without this, an error that occurs at once on each new session restarts the
    /// audio engine and recognizer in a tight loop.
    private func restart(engine: TeleprompterEngine) {
        guard isListening else { return }
        let lasted = sessionStartDate.map { Date.now.timeIntervalSince($0) } ?? 0
        quickFailures = lasted < 2 ? quickFailures + 1 : 0
        teardown()
        if quickFailures == 0 {
            start(engine: engine)
            return
        }
        guard quickFailures < Self.maxQuickFailures else {
            didFail = true
            return
        }
        let pending = sessionID
        let delay = 0.5 * Double(quickFailures)
        Task { [weak self, weak engine] in
            try? await Task.sleep(for: .seconds(delay))
            // `stop()` or a new `start()` during the delay changes `sessionID`.
            guard let self, let engine, self.sessionID == pending, !self.isListening else { return }
            self.start(engine: engine)
        }
    }

    private func handle(result: SFSpeechRecognitionResult, engine: TeleprompterEngine) {
        guard sessionStartDate != nil else { return }
        let now = Date.now
        wpmSamples.append((now, result.bestTranscription.segments.count))
        // Keep one sample at or before the window start, so the window is full length.
        while wpmSamples.count > 1, wpmSamples[1].0 <= now.addingTimeInterval(-Self.wpmWindow) {
            wpmSamples.removeFirst()
        }
        guard let wpm = Self.windowedWPM(samples: wpmSamples) else { return }
        measuredWPM = wpm

        // Results arrive at an uneven rate (fast speech gives more), so the correction
        // depends on the time since the last one, not on the number of results.
        let elapsed = min(lastAdjustDate.map { now.timeIntervalSince($0) } ?? Self.smoothingStep, 1)
        lastAdjustDate = now
        let factor = Self.smoothingFactor(damping: sensitivity.dampingFactor, elapsed: elapsed)

        let target = Self.targetMultiplier(wpm: wpm, baseWPM: engine.baseWPM, manualOffset: engine.manualSpeedOffset)
        engine.speedMultiplier += (target - engine.speedMultiplier) * factor
    }

    /// The measured pace as a multiplier of the script's pace, plus the user's own
    /// speed changes, clamped to the engine's range.
    nonisolated static func targetMultiplier(wpm: Double, baseWPM: Int, manualOffset: Double) -> Double {
        let target = wpm / Double(max(baseWPM, 1)) + manualOffset
        return min(max(target, TeleprompterEngine.speedMultiplierRange.lowerBound), TeleprompterEngine.speedMultiplierRange.upperBound)
    }

    /// Words per minute between the oldest and newest sample, or nil for less than 2
    /// seconds of samples. A partial result can revise the transcript to fewer words,
    /// so the result is never negative.
    nonisolated static func windowedWPM(samples: [(Date, Int)]) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.0.timeIntervalSince(first.0)
        guard span >= 2 else { return nil }
        return Double(max(last.1 - first.1, 0)) / span * 60
    }

    /// `VoiceTrackingSensitivity.dampingFactor` is the fraction of the speed gap closed
    /// in each `smoothingStep` of time.
    nonisolated static let smoothingStep: TimeInterval = 0.2

    /// The fraction of the speed gap to close after `elapsed` seconds.
    nonisolated static func smoothingFactor(damping: Double, elapsed: TimeInterval) -> Double {
        1 - pow(1 - damping, elapsed / smoothingStep)
    }

    nonisolated private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(frameLength))
        return min(Double(rms) * 12, 1)
    }
}
