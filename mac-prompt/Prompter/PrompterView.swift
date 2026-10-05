//
//  PrompterView.swift
//  mac-prompt
//
//  The immersive teleprompter window: camera passthrough (or a plain background),
//  scrolling script text behind a reading-guide band, and the floating glass control
//  bar. Opened from EditorView via `openWindow(id: "prompter", value: script.id)`.

import AVFoundation
import SwiftData
import SwiftUI

struct PrompterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.theme) private var theme

    let scriptID: UUID?

    @AppStorage(AppSettingsKey.voiceTrackingEnabled) private var voiceTrackingEnabled = true
    @AppStorage(AppSettingsKey.voiceTrackingSensitivity) private var sensitivityRaw = VoiceTrackingSensitivity.balanced.rawValue
    @AppStorage(AppSettingsKey.cameraPassthroughEnabled) private var cameraPassthroughEnabled = true
    @AppStorage(AppSettingsKey.cameraDeviceID) private var cameraDeviceID = ""

    @State private var engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
    @State private var voiceTracker = VoiceTracker()
    @StateObject private var recorder = RecordingController()

    @State private var didConfigure = false
    // Fetched once in `configure()` and cached, rather than re-querying SwiftData from
    // a computed property on every render.
    @State private var script: Script?
    /// `script.body` with markup removed, computed only when the body changes. The
    /// scrolling text re-renders on every frame while playing, and running the markup
    /// regexes over the whole script on each frame is wasted work.
    @State private var displayText = ""

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
            PrompterKeyCatcherView(onKeyPress: handle)
        )
        .frame(minWidth: 900, minHeight: 600)
        .task { await configure() }
        // Also runs once when `configure()` first loads the script (nil to its body).
        // Later changes are live edits from the editor window.
        .onChange(of: script?.body) { _, _ in
            guard let script else { return }
            displayText = Script.plainDisplayText(from: script.body)
            engine.wordCount = script.wordCount
        }
        .onChange(of: cameraPassthroughEnabled) { _, enabled in
            Task { await updateCameraPassthrough(enabled: enabled) }
        }
        .onChange(of: cameraDeviceID) { _, deviceID in
            // Switch only a camera that is already running. Reconfiguring removes the
            // movie output, which would cut a recording, so during one the new camera
            // is used from the next session.
            guard recorder.isCameraReady, !recorder.isRecording else { return }
            recorder.configure(deviceID: deviceID.isEmpty ? nil : deviceID)
        }
        .onChange(of: voiceTrackingEnabled) { _, enabled in
            Task { await updateVoiceTracking(enabled: enabled) }
        }
        .onChange(of: sensitivityRaw) { _, raw in
            voiceTracker.sensitivity = VoiceTrackingSensitivity(rawValue: raw) ?? .balanced
        }
        .onDisappear {
            engine.stop()
            voiceTracker.stop()
            recorder.stop()
        }
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
            if recorder.isRecording {
                HStack(spacing: 7) {
                    Circle().fill(theme.rec).frame(width: 7, height: 7)
                    Text("REC  \(recorder.elapsedTimeText)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(theme.textDim)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassPill()
                .padding(.top, 14)
            }
            Spacer()
        }
    }

    // MARK: - Setup

    private func configure() async {
        guard !didConfigure else { return }
        didConfigure = true

        guard let scriptID else { return }
        let descriptor = FetchDescriptor<Script>(predicate: #Predicate<Script> { $0.id == scriptID })
        guard let fetchedScript = try? modelContext.fetch(descriptor).first else { return }
        script = fetchedScript

        let defaultSizeRaw = UserDefaults.standard.string(forKey: AppSettingsKey.defaultPrompterFontSize) ?? ""
        let defaultSize = PrompterFontSize(rawValue: defaultSizeRaw)?.points ?? 48

        engine.baseWPM = fetchedScript.targetWPM
        engine.fontSize = defaultSize
        engine.lineSpacing = fetchedScript.lineSpacingStyle.points
        voiceTracker.sensitivity = VoiceTrackingSensitivity(rawValue: sensitivityRaw) ?? .balanced

        // `.task` cancels this Task automatically when the view disappears, but that
        // cancellation can't interrupt an in-flight system permission dialog — only
        // the `await` returning. Re-check after each one before touching hardware, so
        // closing the window while a dialog is still up can't leave the camera/mic
        // starting up moments after the window (and every other cleanup path) is gone.
        // A denied permission skips only its own feature: no camera must not also mean
        // no voice tracking.
        if cameraPassthroughEnabled {
            let granted = await RecordingController.requestCameraAccess()
            guard !Task.isCancelled else { return }
            if granted {
                recorder.configure(deviceID: cameraDeviceID.isEmpty ? nil : cameraDeviceID)
                recorder.start()
            }
        }

        if voiceTrackingEnabled {
            let granted = await VoiceTracker.requestPermissions()
            guard !Task.isCancelled else { return }
            if granted { voiceTracker.start(engine: engine) }
        }

        // Start scrolling only after the permission dialogs, so the first lines do not
        // scroll past behind them.
        engine.start()
    }

    /// Reacts to the Camera Passthrough setting changing while this Prompter window is
    /// already open, so toggling it doesn't leave the camera view blank (turned on with
    /// the session never configured/started) or the capture session silently still
    /// running after being switched off (camera indicator light staying lit).
    private func updateCameraPassthrough(enabled: Bool) async {
        guard didConfigure else { return }
        if enabled {
            if recorder.isCameraReady {
                recorder.start()
                return
            }
            let granted = await RecordingController.requestCameraAccess()
            guard granted else { return }
            recorder.configure(deviceID: cameraDeviceID.isEmpty ? nil : cameraDeviceID)
            recorder.start()
        } else {
            recorder.stop()
        }
    }

    /// Reacts to the Voice Tracking setting changing while this Prompter window is
    /// open, so switching it off stops the tracker instead of letting it keep changing
    /// the speed with its indicator hidden.
    private func updateVoiceTracking(enabled: Bool) async {
        guard didConfigure else { return }
        if enabled {
            let granted = await VoiceTracker.requestPermissions()
            guard granted else { return }
            voiceTracker.start(engine: engine)
        } else {
            voiceTracker.stop()
        }
    }

    private func close() {
        engine.stop()
        voiceTracker.stop()
        recorder.stop()
        dismissWindow()
    }

    private func handle(key: PrompterKey) {
        switch key {
        case .space: engine.togglePlayPause()
        case .arrowUp: engine.adjustSpeedMultiplier(by: 0.1)
        case .arrowDown: engine.adjustSpeedMultiplier(by: -0.1)
        case .r: recorder.isRecording ? recorder.stopRecording() : recorder.startRecording()
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
                // `.position()` places the Text's own center at an exact, unambiguous
                // point in this ZStack's coordinate space — see the comment on
                // `TeleprompterEngine.scrollOffset` for why that (rather than
                // `.offset()` relative to an implicit container alignment) is what
                // makes the start/end bounds reason about correctly.
                Text(text)
                    .font(.system(size: engine.fontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(engine.lineSpacing)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                    .frame(width: max(outerGeo.size.width - 120, 0))
                    .background(
                        GeometryReader { innerGeo in
                            Color.clear
                                .onAppear {
                                    engine.updateGeometry(availableHeight: outerGeo.size.height, textHeight: innerGeo.size.height)
                                    engine.resetToStart()
                                }
                                // Any later change in either height re-measures. This
                                // covers the script text loading (it starts out empty,
                                // because `configure()` fetches it after first appearance),
                                // live edits, A+/A-, and window resizes or full screen,
                                // which re-wrap the text. `updateGeometry` keeps the
                                // reader's progress, so none of these jump to the top.
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
