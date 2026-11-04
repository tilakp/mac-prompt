//
//  RecordingController.swift
//  mac-prompt
//
//  Owns the AVCaptureSession used for both the full-bleed camera passthrough
//  background and recording. Recordings are written into the app's own sandboxed
//  Documents directory, which is always writable inside the sandbox without any
//  extra user-facing file picker or entitlement beyond camera/microphone access.

// AVFoundation does not mark its types Sendable. They are used across threads only
// through `sessionQueue`, which serializes all access.
@preconcurrency import AVFoundation

@MainActor
final class RecordingController: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var isCameraReady = false
    @Published private(set) var lastRecordingURL: URL?

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var elapsedTimer: Timer?
    private var recordingStartDate: Date?

    /// Every call that touches `session` or `movieOutput` runs on this one serial queue.
    /// AVCaptureSession is not thread-safe, and its configuration and start/stop calls
    /// block, so they must not run on the main thread or in the Swift concurrency pool.
    /// The queue also keeps them in the order they were asked for: closing the Prompter
    /// right after opening it cannot let `startRunning()` run after `stopRunning()`.
    private let sessionQueue = DispatchQueue(label: "com.patelt.mac-prompt.capture-session")
    /// True between `start()` and `stop()`, so an interruption that ends after `stop()`
    /// does not mark the camera ready again.
    private var wantsRunning = false
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
                    guard let self, self.wantsRunning else { return }
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
    /// (nil = system default). Safe to call again to switch cameras. The work runs on
    /// `sessionQueue`; `isCameraReady` changes when it is done.
    func configure(deviceID: String?) {
        sessionQueue.async { [weak self, session, movieOutput] in
            let ready = Self.configureSession(session, movieOutput: movieOutput, deviceID: deviceID)
            Task { @MainActor in
                // Callers call `start()` right after this. A `stop()` that came first
                // must not be undone by a configuration that finishes later.
                guard let self else { return }
                self.isCameraReady = ready && self.wantsRunning
            }
        }
    }

    private nonisolated static func configureSession(
        _ session: AVCaptureSession,
        movieOutput: AVCaptureMovieFileOutput,
        deviceID: String?
    ) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.sessionPreset = .high

        let device: AVCaptureDevice? = deviceID.flatMap(AVCaptureDevice.init(uniqueID:))
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)

        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        if session.canAddInput(input) { session.addInput(input) }

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        return true
    }

    func start() {
        wantsRunning = true
        sessionQueue.async { [session] in session.startRunning() }
    }

    func stop() {
        if isRecording { stopRecording() }
        wantsRunning = false
        // A stopped session cannot record. Without this, R with passthrough switched
        // off would start a recording that fails at once. `configure` makes it ready again.
        isCameraReady = false
        sessionQueue.async { [session] in session.stopRunning() }
    }

    func startRecording() {
        guard !isRecording, isCameraReady else { return }
        let url = RecordingController.newRecordingURL()
        sessionQueue.async { [movieOutput] in
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        isRecording = true
        elapsedSeconds = 0
        let startDate = Date.now
        recordingStartDate = startDate
        // Computed from the start date, so it does not drift. `.common` mode keeps it
        // updating while a menu is open.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartDate else { return }
                // `@Published` notifies on every assignment, even of an equal value,
                // and each notification redraws the whole Prompter view.
                let seconds = Int(Date.now.timeIntervalSince(start))
                if seconds != self.elapsedSeconds { self.elapsedSeconds = seconds }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [movieOutput] in movieOutput.stopRecording() }
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
        // (e.g. the session stopped); it then sets this key, and the file is usable.
        let finished = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        Task { @MainActor in
            self.isRecording = false
            self.elapsedTimer?.invalidate()
            self.elapsedTimer = nil
            self.recordingStartDate = nil
            if finished {
                self.lastRecordingURL = outputFileURL
            }
        }
    }
}
