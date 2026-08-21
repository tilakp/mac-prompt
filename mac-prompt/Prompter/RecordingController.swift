//
//  RecordingController.swift
//  mac-prompt
//
//  Owns the AVCaptureSession used for both the full-bleed camera passthrough
//  background and recording. Recordings are written into the app's own sandboxed
//  Documents directory, which is always writable inside the sandbox without any
//  extra user-facing file picker or entitlement beyond camera/microphone access.

import AVFoundation

@MainActor
final class RecordingController: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var isCameraReady = false
    @Published private(set) var lastRecordingURL: URL?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var elapsedTimer: Timer?

    /// The most recently scheduled start/stop, so a new start/stop always runs after
    /// whichever one preceded it finishes touching the hardware — see `start()`/`stop()`.
    private var pendingSessionTask: Task<Void, Never>?
    private var interruptionObservers: [NSObjectProtocol] = []

    static func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    override init() {
        super.init()
        let center = NotificationCenter.default
        // If another app (or another Prompter window) takes the camera, or the
        // session hits a runtime error, reflect that in isCameraReady so the record
        // button and camera background stop claiming readiness that no longer holds.
        interruptionObservers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.isCameraReady = false }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.isCameraReady = false }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.session.inputs.isEmpty else { return }
                    self.isCameraReady = true
                }
            },
        ]
    }

    deinit {
        let center = NotificationCenter.default
        for observer in interruptionObservers { center.removeObserver(observer) }
    }

    /// (Re)configures the session's inputs/outputs for the given camera device
    /// (nil = system default). Safe to call again to switch cameras.
    func configure(deviceID: String?) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.sessionPreset = .high

        let device: AVCaptureDevice? = deviceID.flatMap(AVCaptureDevice.init(uniqueID:))
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)

        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            isCameraReady = false
            return
        }
        if session.canAddInput(input) { session.addInput(input) }

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        isCameraReady = true
    }

    func start() {
        // AVCaptureSession.startRunning()/stopRunning() block, so Apple's guidance is to
        // call them off the main thread. Chaining onto `pendingSessionTask` (rather than
        // firing an independent detached task each time) guarantees a start and a stop
        // requested close together run in the order they were requested instead of
        // racing — e.g. closing the Prompter window right after opening it must not let
        // a still-in-flight startRunning() begin *after* the matching stopRunning() has
        // already run, which would leave the camera on with nothing left to stop it.
        let previous = pendingSessionTask
        pendingSessionTask = Task.detached { [session] in
            _ = await previous?.value
            session.startRunning()
        }
    }

    func stop() {
        if isRecording { stopRecording() }
        let previous = pendingSessionTask
        pendingSessionTask = Task.detached { [session] in
            _ = await previous?.value
            session.stopRunning()
        }
    }

    func startRecording() {
        guard !isRecording, isCameraReady else { return }
        movieOutput.startRecording(to: RecordingController.newRecordingURL(), recordingDelegate: self)
        isRecording = true
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    var elapsedTimeText: String { Script.formatDuration(totalSeconds: elapsedSeconds) }

    static func recordingsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func newRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        return recordingsDirectory().appendingPathComponent("Prompt-\(stamp).mov")
    }
}

extension RecordingController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            self.elapsedTimer?.invalidate()
            self.elapsedTimer = nil
            if error == nil {
                self.lastRecordingURL = outputFileURL
            }
        }
    }
}
