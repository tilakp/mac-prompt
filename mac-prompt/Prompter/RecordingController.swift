//
//  RecordingController.swift
//  mac-prompt
//
//  Owns the capture session behind the Prompter's camera background and recordings.
//  Recordings go to the app's sandboxed Documents folder, which needs no extra
//  entitlement.

// AVFoundation does not mark its types Sendable. They are used across threads only
// through `sessionQueue`, which serializes all access.
@preconcurrency import AVFoundation
import Observation

@MainActor
@Observable
final class RecordingController: NSObject {
    private(set) var isRecording = false
    /// When the current recording started. Views show the elapsed time with
    /// `Text(_:style: .timer)`, so no timer is needed.
    private(set) var recordingStartDate: Date?
    private(set) var isCameraReady = false
    private(set) var lastRecordingURL: URL?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()

    /// Every call that touches `session` or `movieOutput` runs on this one serial queue.
    /// AVCaptureSession is not thread-safe, and its calls block, so they must not run on
    /// the main thread. The queue also keeps them in order: closing the Prompter right
    /// after opening it cannot let `startRunning()` run after `stopRunning()`.
    private let sessionQueue = DispatchQueue(label: "com.patelt.mac-prompt.capture-session")
    /// True between `start()` and `stop()`. Late events (a configuration that finishes,
    /// an interruption that ends) must not mark a stopped camera ready.
    @ObservationIgnored private var wantsRunning = false
    /// Set by the one automatic restart after a runtime error, so an error that repeats
    /// does not restart the session forever. `configure` clears it.
    @ObservationIgnored private var didRestartAfterRuntimeError = false
    @ObservationIgnored private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    /// All live controllers, so the app can finish their recordings before it quits.
    private static let all = NSHashTable<RecordingController>.weakObjects()

    /// Asks for the camera, then for the mic so recordings have sound. Returns whether
    /// the camera is allowed. Without the mic, recordings have no sound track.
    static func requestAccess() async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return true
    }

    static var isAnyRecording: Bool { all.allObjects.contains(where: \.isRecording) }

    /// Stops every recording and returns when all their files are complete.
    static func finishAllRecordings() async {
        for controller in all.allObjects { await controller.finishRecording() }
    }

    override init() {
        super.init()
        Self.all.add(self)
        let center = NotificationCenter.default
        // `queue: .main` delivers these on the main thread.
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isCameraReady = false }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.wantsRunning else { return }
                    self.isCameraReady = true
                }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartAfterRuntimeError() }
            },
        ]
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// (Re)configures the session for the given camera (nil = system default). Safe to
    /// call again to switch cameras. `isCameraReady` changes when the work is done.
    func configure(deviceID: String?) {
        didRestartAfterRuntimeError = false
        sessionQueue.async { [weak self, session, movieOutput] in
            let ready = Self.configureSession(session, movieOutput: movieOutput, deviceID: deviceID)
            Task { @MainActor in
                // Callers call `start()` right after this; a `stop()` that came between
                // must not be undone by this late result.
                guard let self else { return }
                self.isCameraReady = ready && self.wantsRunning
            }
        }
    }

    /// Returns true only if the session can record: it has the camera input and the
    /// movie output. Recording without them raises an exception.
    private nonisolated static func configureSession(
        _ session: AVCaptureSession,
        movieOutput: AVCaptureMovieFileOutput,
        deviceID: String?
    ) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }

        let device: AVCaptureDevice? = deviceID.flatMap(AVCaptureDevice.init(uniqueID:))
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        // Optional: with no mic or no mic permission, recordings have no sound.
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else { return false }
        session.addOutput(movieOutput)
        return true
    }

    func start() {
        wantsRunning = true
        sessionQueue.async { [session] in session.startRunning() }
    }

    func stop() {
        stopRecording()
        wantsRunning = false
        // A stopped session cannot record. `configure` makes it ready again.
        isCameraReady = false
        sessionQueue.async { [session] in session.stopRunning() }
    }

    /// Restarts the session one time (e.g. after media services reset or the camera
    /// was reconnected). If the error comes back, the camera stays off.
    private func restartAfterRuntimeError() {
        isCameraReady = false
        guard wantsRunning, !didRestartAfterRuntimeError else { return }
        didRestartAfterRuntimeError = true
        sessionQueue.async { [weak self, session] in
            session.startRunning()
            let running = session.isRunning
            Task { @MainActor in
                guard let self, running, self.wantsRunning else { return }
                self.isCameraReady = true
            }
        }
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard !isRecording, isCameraReady else { return }
        let url = Self.newRecordingURL()
        isRecording = true
        recordingStartDate = .now
        sessionQueue.async { [movieOutput] in
            // The camera can go away after `isCameraReady` was set (e.g. unplugged).
            // Recording with no active video connection raises an exception.
            guard movieOutput.connection(with: .video)?.isActive == true else {
                Task { @MainActor in self.recordingDidEnd(savedTo: nil) }
                return
            }
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [movieOutput] in movieOutput.stopRecording() }
    }

    /// Stops the recording and returns when its file is complete.
    func finishRecording() async {
        guard isRecording else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
            stopRecording()
        }
    }

    private func recordingDidEnd(savedTo url: URL?) {
        isRecording = false
        recordingStartDate = nil
        if let url { lastRecordingURL = url }
        for waiter in finishWaiters { waiter.resume() }
        finishWaiters = []
    }

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
        let directory = recordingsDirectory()
        // Two takes started in the same second would get the same name, and
        // AVCaptureMovieFileOutput fails to record to a file that already exists.
        var url = directory.appendingPathComponent("Prompt-\(stamp).mov")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("Prompt-\(stamp)-\(suffix).mov")
            suffix += 1
        }
        return url
    }
}

extension RecordingController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // AVFoundation can report an error for a file that still finished correctly
        // (e.g. the session stopped). It then sets this key, and the file is usable.
        let finished = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        Task { @MainActor in self.recordingDidEnd(savedTo: finished ? outputFileURL : nil) }
    }
}
