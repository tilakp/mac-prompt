//
//  PrompterControlBar.swift
//  mac-prompt
//
//  The floating control bar of the Prompter: play/pause, speed, font size, mirror
//  flip, the voice-tracking indicator, record, and close.

import AppKit
import SwiftUI

struct PrompterControlBar: View {
    @Environment(\.theme) private var theme
    let engine: TeleprompterEngine
    let voiceTracker: VoiceTracker
    let recorder: RecordingController
    var voiceTrackingEnabled: Bool
    var cameraEnabled: Bool
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            playPauseButton
            separator
            iconButton("Slower", systemImage: "minus") { engine.adjustSpeedMultiplier(by: -0.1) }
            Text(engine.speedMultiplierText)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 46)
                .accessibilityLabel("Speed \(engine.speedMultiplierText)")
            iconButton("Faster", systemImage: "plus") { engine.adjustSpeedMultiplier(by: 0.1) }
            separator
            textButton("A–", label: "Smaller text") { engine.adjustFontSize(by: -4) }
            textButton("A+", label: "Larger text") { engine.adjustFontSize(by: 4) }
            separator
            iconButton(
                "Mirror flip",
                systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                isActive: engine.mirrored
            ) {
                engine.mirrored.toggle()
            }

            if voiceTrackingEnabled {
                separator
                voiceTrackingIndicator
            }

            if cameraEnabled {
                Spacer().frame(width: 12)
                recordButton
                if let url = recorder.lastRecordingURL, !recorder.isRecording {
                    iconButton("Reveal recording in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }

            separator
            iconButton("Close Prompter", systemImage: "xmark", action: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPill()
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
    }

    private var playPauseButton: some View {
        Button {
            engine.togglePlayPause()
        } label: {
            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(theme.accent, in: Circle())
                .foregroundStyle(theme.onAccent)
        }
        .buttonStyle(.plain)
        .help(engine.isPlaying ? "Pause" : "Play")
        .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
    }

    private func iconButton(
        _ label: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isActive ? theme.text : theme.textDim)
                .background(isActive ? theme.text.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func textButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.heading(13))
                .frame(width: 36, height: 36)
                .foregroundStyle(theme.textDim)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 22)
    }

    @ViewBuilder private var voiceTrackingIndicator: some View {
        if voiceTracker.didFail {
            Button {
                voiceTracker.retry(engine: engine)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Retry")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.amber)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .help("Voice tracking stopped because speech recognition failed. Click to try again.")
            .accessibilityLabel("Retry voice tracking")
        } else {
            voiceTrackingLevel
        }
    }

    private var voiceTrackingLevel: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(voiceTracker.isListening ? theme.teal : theme.textFaint)
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.teal)
                        .frame(width: 2.5, height: barHeight(for: i))
                        .animation(.easeInOut(duration: 0.15), value: voiceTracker.micLevel)
                }
            }
            .frame(height: 15, alignment: .bottom)
            Text(voiceTracker.isListening ? "Tracking" : "Off")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(voiceTracker.isListening ? theme.teal : theme.textFaint)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice tracking \(voiceTracker.isListening ? "on" : "off")")
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = [5, 11, 8, 13][index]
        let boost = CGFloat(voiceTracker.micLevel) * 10
        return min(base + boost, 18)
    }

    private var recordButton: some View {
        Button(action: recorder.toggleRecording) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(theme.rec).frame(width: 36, height: 36)
                        .shadow(color: theme.rec.opacity(0.4), radius: 0)
                        .overlay(Circle().stroke(theme.rec.opacity(0.25), lineWidth: 4).scaleEffect(1.3))
                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 12, height: 12)
                    } else {
                        Circle().fill(.white).frame(width: 12, height: 12)
                    }
                }
                if let start = recorder.recordingStartDate {
                    Text(start, style: .timer)
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.text)
                }
            }
            .padding(.trailing, recorder.isRecording ? 14 : 0)
            .padding(.leading, 2)
            .background(
                Capsule().fill(theme.rec.opacity(recorder.isRecording ? 0.16 : 0))
            )
        }
        .buttonStyle(.plain)
        .disabled(!recorder.isCameraReady)
        .help(recorder.isRecording ? "Stop recording" : "Start recording")
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
    }
}
