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

import AVFoundation
import Speech

@MainActor
final class VoiceTracker: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var micLevel: Double = 0
    @Published private(set) var measuredWPM: Double?

    var sensitivity: VoiceTrackingSensitivity = .balanced

    private let audioEngine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Touched only from the audio tap's render-thread callback below (never from
    /// MainActor code), which AVAudioEngine always invokes serially on the same
    /// thread — safe without extra synchronization. Throttles how often the tap
    /// hops to MainActor to publish `micLevel`: the callback fires ~40-50x/sec for
    /// the whole session (30-60+ min), but the control bar only animates 4 bars, so
    /// there's no UX benefit to updating faster than ~20Hz — just actor-hop overhead.
    nonisolated(unsafe) private var lastLevelUpdate = Date.distantPast
    private var sessionStartDate: Date?

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
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        sessionStartDate = .now

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
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

        task = recognizer.recognitionTask(with: request) { [weak self, weak engine] result, error in
            Task { @MainActor [weak self, weak engine] in
                guard let self, let engine else { return }
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
