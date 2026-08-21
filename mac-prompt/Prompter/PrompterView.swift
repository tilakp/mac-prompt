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

    @StateObject private var engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
    @StateObject private var voiceTracker = VoiceTracker()
    @StateObject private var recorder = RecordingController()

    @State private var didConfigure = false
    @State private var hasCentered = false
    // Fetched once in `configure()` and cached, rather than re-querying SwiftData from
    // a computed property: `displayText` is read from `scrollingText`, which re-renders
    // on every ~8ms scroll-timer tick while playing, and a fresh FetchDescriptor on that
    // hot path would add redundant database work throughout every session.
    @State private var script: Script?

    var body: some View {
        ZStack {
            background
            legibilityScrim
            readingGuideBand
            scrollingText
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
        .onChange(of: cameraPassthroughEnabled) { _, enabled in
            Task { await updateCameraPassthrough(enabled: enabled) }
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
            CameraPreviewView(session: recorder.session)
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

    private var scrollingText: some View {
        GeometryReader { outerGeo in
            ZStack {
                Text(displayText)
                    .font(.system(size: engine.fontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(engine.lineSpacing)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                    .offset(y: engine.scrollOffset)
                    .padding(.horizontal, 60)
                    .background(
                        GeometryReader { innerGeo in
                            Color.clear
                                .onAppear { syncGeometry(outer: outerGeo, inner: innerGeo) }
                                .onChange(of: engine.fontSize) { _, _ in syncGeometry(outer: outerGeo, inner: innerGeo) }
                        }
                    )
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

    private var displayText: String {
        guard let script else { return "" }
        return Script.plainDisplayText(from: script.body)
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
        engine.start()

        // `.task` cancels this Task automatically when the view disappears, but that
        // cancellation can't interrupt an in-flight system permission dialog — only
        // the `await` returning. Re-check after each one before touching hardware, so
        // closing the window while a dialog is still up can't leave the camera/mic
        // starting up moments after the window (and every other cleanup path) is gone.
        if cameraPassthroughEnabled {
            let granted = await RecordingController.requestCameraAccess()
            guard !Task.isCancelled, granted else { return }
            recorder.configure(deviceID: cameraDeviceID.isEmpty ? nil : cameraDeviceID)
            recorder.start()
        }

        if voiceTrackingEnabled {
            let granted = await VoiceTracker.requestPermissions()
            guard !Task.isCancelled, granted else { return }
            voiceTracker.start(engine: engine)
        }
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

    private func syncGeometry(outer: GeometryProxy, inner: GeometryProxy) {
        let availableHeight = outer.size.height
        let textHeight = inner.size.height
        engine.updateGeometry(availableHeight: availableHeight, textHeight: textHeight)
        // Only auto-center once, on first layout — re-running this on every geometry
        // change (e.g. an A+/A- font-size tweak mid-read) used to compare
        // `scrollOffset == 0` as an "unset" sentinel, but scrollOffset legitimately
        // passes through exactly 0 during normal playback, which could snap the view
        // back to center mid-read. `updateGeometry` above already re-clamps
        // scrollOffset into bounds for the new geometry, which is all a resize needs.
        if !hasCentered {
            engine.scrollOffset = availableHeight / 2
            hasCentered = true
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
