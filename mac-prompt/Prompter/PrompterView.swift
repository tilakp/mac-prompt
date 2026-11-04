//
//  PrompterView.swift
//  mac-prompt
//
//  The teleprompter window: camera passthrough (or a plain background), scrolling
//  script text behind a reading-guide band, and the floating control bar. Opened from
//  EditorView with `openWindow(id: "prompter", value: script.id)`.

import SwiftData
import SwiftUI

extension Notification.Name {
    /// Posted by a Prompter window as it starts, with its script's `id` as the object.
    /// Only one Prompter is open at a time: each one runs its own camera session and
    /// speech recognizer, and two of them take the camera and mic from each other.
    static let prompterDidOpen = Notification.Name("prompterDidOpen")
    /// Posted on the main thread just before a script is permanently deleted, with the
    /// script's `id` as the object. A Prompter for that script drops its reference and
    /// closes: reading a deleted SwiftData model can stop the app.
    static let scriptWillBeDeleted = Notification.Name("scriptWillBeDeleted")
}

struct PrompterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.theme) private var theme

    let scriptID: UUID?

    @AppStorage(AppSettingsKey.voiceTrackingEnabled) private var voiceTrackingEnabled = true
    @AppStorage(AppSettingsKey.voiceTrackingSensitivity) private var sensitivity = VoiceTrackingSensitivity.balanced
    @AppStorage(AppSettingsKey.cameraPassthroughEnabled) private var cameraPassthroughEnabled = true
    @AppStorage(AppSettingsKey.cameraDeviceID) private var cameraDeviceID = ""
    @AppStorage(AppSettingsKey.defaultPrompterFontSize) private var defaultFontSize = PrompterFontSize.medium

    @State private var engine = TeleprompterEngine(
        baseWPM: AppSettingsDefaults.wpm,
        fontSize: PrompterFontSize.medium.points,
        lineSpacing: LineSpacingStyle.comfortable.points
    )
    @State private var voiceTracker = VoiceTracker()
    @State private var recorder = RecordingController()

    @State private var didConfigure = false
    /// The camera and voice settings as this window last applied them; nil until
    /// `configure()` runs. Later changes come from the Settings window.
    @State private var appliedCameraSetting: Bool?
    @State private var appliedVoiceSetting: Bool?
    /// Fetched once in `configure()`, not queried again on each render.
    @State private var script: Script?
    /// `script.body` without markup. The scrolling text renders on every frame while
    /// playing, so the markup regexes must not run in its body.
    @State private var displayText = ""
    @State private var didLoadText = false

    var body: some View {
        ZStack {
            background
            legibilityScrim
            readingGuideBand
            PrompterScrollingText(text: displayText, engine: engine)
            topStatusPill
            VStack {
                Spacer()
                PrompterControlBar(
                    engine: engine,
                    voiceTracker: voiceTracker,
                    recorder: recorder,
                    voiceTrackingEnabled: voiceTrackingEnabled,
                    cameraEnabled: cameraPassthroughEnabled,
                    onClose: close
                )
                .padding(.bottom, 26)
            }
        }
        .scaleEffect(x: engine.mirrored ? -1 : 1, y: 1)
        .background(
            // The display link follows this view's window to whichever screen it is on.
            PrompterKeyCatcherView(onKeyPress: handle, onAttach: { engine.attach(to: $0) })
        )
        .frame(minWidth: 900, minHeight: 600)
        .task { await configure() }
        // Runs when `configure()` loads the script, and again for each live edit from
        // the editor. Edits wait until typing pauses: each update runs the markup
        // regexes and lays out the whole script again.
        .task(id: script?.body) {
            guard let script else { return }
            if didLoadText {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            didLoadText = true
            displayText = ScriptMarkup.plainText(from: script.body)
            engine.wordCount = script.wordCount
        }
        .onChange(of: script?.targetWPM) { _, wpm in
            if let wpm { engine.baseWPM = wpm }
        }
        .onChange(of: script?.lineSpacingStyleRaw) { _, _ in
            if let script { engine.lineSpacing = script.lineSpacingStyle.points }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prompterDidOpen)) { note in
            guard let id = note.object as? UUID, id != scriptID else { return }
            close()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scriptWillBeDeleted)) { note in
            guard let id = note.object as? UUID, id == scriptID else { return }
            script = nil
            close()
        }
        // `.task(id:)`, not `.onChange` with a `Task`: SwiftUI cancels it when the
        // window closes or the setting changes again, so a permission dialog that
        // returns late cannot turn the camera or mic on.
        .task(id: cameraPassthroughEnabled) { await applyCameraSetting() }
        .task(id: voiceTrackingEnabled) { await applyVoiceSetting() }
        .onChange(of: cameraDeviceID) { _, deviceID in
            // Switch only a camera that is already running. Reconfiguring removes the
            // movie output and would cut a recording, so during one the new camera is
            // used from the next session.
            guard recorder.isCameraReady, !recorder.isRecording else { return }
            recorder.configure(deviceID: deviceID.isEmpty ? nil : deviceID)
        }
        .onChange(of: sensitivity) { _, sensitivity in
            voiceTracker.sensitivity = sensitivity
        }
        .onDisappear(perform: stopSession)
    }

    // MARK: - Layers

    @ViewBuilder private var background: some View {
        if cameraPassthroughEnabled {
            CameraPreviewView(session: recorder.session, isCameraReady: recorder.isCameraReady)
                .ignoresSafeArea()
        } else {
            theme.bg.ignoresSafeArea()
        }
    }

    private var legibilityScrim: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(cameraPassthroughEnabled ? 0.65 : 0.15),
                .clear,
                .clear,
                Color.black.opacity(cameraPassthroughEnabled ? 0.55 : 0.2),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var readingGuideBand: some View {
        GeometryReader { geo in
            let bandHeight: CGFloat = 74
            let top = geo.size.height / 2 - bandHeight / 2
            ZStack {
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1).position(x: geo.size.width / 2, y: top)
                Rectangle().fill(.white.opacity(0.16)).frame(height: 1).position(x: geo.size.width / 2, y: top + bandHeight)
            }
        }
        .allowsHitTesting(false)
    }

    private var topStatusPill: some View {
        VStack {
            if let start = recorder.recordingStartDate {
                HStack(spacing: 7) {
                    Circle().fill(theme.rec).frame(width: 7, height: 7)
                    Text("REC")
                    Text(start, style: .timer).monospacedDigit()
                }
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(theme.textDim)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassPill()
                .padding(.top, 14)
                .accessibilityElement(children: .combine)
            }
            Spacer()
        }
    }

    // MARK: - Session

    private func configure() async {
        guard !didConfigure else { return }
        didConfigure = true

        guard let scriptID else { return }
        // Before the permission dialogs and the camera: another Prompter closes and
        // releases the camera and mic.
        NotificationCenter.default.post(name: .prompterDidOpen, object: scriptID)
        let descriptor = FetchDescriptor<Script>(predicate: #Predicate<Script> { $0.id == scriptID })
        guard let fetchedScript = try? modelContext.fetch(descriptor).first else { return }
        script = fetchedScript

        engine.baseWPM = fetchedScript.targetWPM
        engine.fontSize = defaultFontSize.points
        engine.lineSpacing = fetchedScript.lineSpacingStyle.points
        voiceTracker.sensitivity = sensitivity
        appliedCameraSetting = cameraPassthroughEnabled
        appliedVoiceSetting = voiceTrackingEnabled

        // A denied permission skips only its own feature: no camera must not also mean
        // no voice tracking.
        if cameraPassthroughEnabled { await startCamera() }
        guard !Task.isCancelled else { return }
        if voiceTrackingEnabled { await startVoiceTracking() }
        guard !Task.isCancelled else { return }

        // Start scrolling only after the permission dialogs, so the first lines do not
        // scroll past behind them.
        engine.start()
    }

    /// Applies a Camera Passthrough change made in Settings while this window is open.
    private func applyCameraSetting() async {
        guard let applied = appliedCameraSetting, applied != cameraPassthroughEnabled else { return }
        appliedCameraSetting = cameraPassthroughEnabled
        if cameraPassthroughEnabled { await startCamera() } else { recorder.stop() }
    }

    /// Applies a Voice Tracking change made in Settings while this window is open.
    private func applyVoiceSetting() async {
        guard let applied = appliedVoiceSetting, applied != voiceTrackingEnabled else { return }
        appliedVoiceSetting = voiceTrackingEnabled
        if voiceTrackingEnabled { await startVoiceTracking() } else { voiceTracker.stop() }
    }

    // Each check after the `await` matters: a permission dialog can return after the
    // window closed (the task is then cancelled) or after the setting was switched off.

    private func startCamera() async {
        let granted = await RecordingController.requestAccess()
        guard granted, !Task.isCancelled, cameraPassthroughEnabled else { return }
        recorder.configure(deviceID: cameraDeviceID.isEmpty ? nil : cameraDeviceID)
        recorder.start()
    }

    private func startVoiceTracking() async {
        let granted = await VoiceTracker.requestPermissions()
        guard granted, !Task.isCancelled, voiceTrackingEnabled else { return }
        voiceTracker.start(engine: engine)
    }

    private func stopSession() {
        engine.stop()
        voiceTracker.stop()
        recorder.stop()
    }

    private func close() {
        stopSession()
        dismissWindow()
    }

    private func handle(key: PrompterKey) {
        switch key {
        case .space: engine.togglePlayPause()
        case .arrowUp: engine.adjustSpeedMultiplier(by: 0.1)
        case .arrowDown: engine.adjustSpeedMultiplier(by: -0.1)
        case .r: recorder.toggleRecording()
        case .m: engine.mirrored.toggle()
        case .escape: close()
        }
    }
}

/// The scrolling script text. A separate view so the per-frame `scrollOffset` change
/// re-renders only this view, not the camera background or the control bar.
private struct PrompterScrollingText: View {
    @Environment(\.theme) private var theme
    let text: String
    let engine: TeleprompterEngine

    var body: some View {
        GeometryReader { outerGeo in
            ZStack {
                // `.position()` puts the Text's center at `scrollOffset` in this ZStack's
                // coordinate space. See `TeleprompterEngine.scrollOffset`.
                Text(text)
                    .font(.system(size: engine.fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(engine.lineSpacing)
                    .frame(width: max(outerGeo.size.width - 120, 0))
                    .background(
                        GeometryReader { innerGeo in
                            Color.clear
                                .onAppear {
                                    engine.updateGeometry(availableHeight: outerGeo.size.height, textHeight: innerGeo.size.height)
                                    engine.resetToStart()
                                }
                                // Measure again when either height changes: the script
                                // loads (it starts empty), a live edit, A+/A-, or a window
                                // resize. `updateGeometry` keeps the reader's progress.
                                .onChange(of: innerGeo.size.height) { _, height in
                                    engine.updateGeometry(availableHeight: outerGeo.size.height, textHeight: height)
                                }
                                .onChange(of: outerGeo.size.height) { _, height in
                                    engine.updateGeometry(availableHeight: height, textHeight: innerGeo.size.height)
                                }
                        }
                    )
                    .position(x: outerGeo.size.width / 2, y: engine.scrollOffset)
            }
            .frame(width: outerGeo.size.width, height: outerGeo.size.height)
            // The shadow is on this clipped, window-sized layer, not on the Text. A blur
            // shadow renders its view offscreen, and the Text of a long script is tens of
            // thousands of points tall. The look is the same: the mask below is clear at
            // the clipped edges.
            .clipped()
            .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.2),
                        .init(color: .black, location: 0.8),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
