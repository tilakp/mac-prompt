//
//  PrompterControlBar.swift
//  mac-prompt
//
//  The floating glass pill from the Prompter mockup: play/pause, speed, font size,
//  mirror flip, a live voice-tracking indicator, record, and close.

import AppKit
import SwiftUI

struct PrompterControlBar: View {
    @Environment(\.theme) private var theme
    @ObservedObject var engine: TeleprompterEngine
    @ObservedObject var voiceTracker: VoiceTracker
    @ObservedObject var recorder: RecordingController
    var voiceTrackingEnabled: Bool
    var cameraEnabled: Bool
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            playPauseButton
            separator
            smallButton(systemImage: "minus") { engine.adjustSpeedMultiplier(by: -0.1) }
            Text(engine.speedMultiplierText)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(theme.text)
                .frame(width: 46)
            smallButton(systemImage: "plus") { engine.adjustSpeedMultiplier(by: 0.1) }
            separator
            smallButton(label: "A–") { engine.adjustFontSize(by: -4) }
            smallButton(label: "A+") { engine.adjustFontSize(by: 4) }
            separator
            smallButton(systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", isActive: engine.mirrored) {
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
                    smallButton(systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .help("Reveal recording in Finder")
                }
            }

            separator
            smallButton(systemImage: "xmark") { onClose() }
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
                .foregroundColor(Color(red: 0.10, green: 0.06, blue: 0.07))
        }
        .buttonStyle(.plain)
    }

    private func smallButton(systemImage: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundColor(isActive ? theme.text : theme.textDim)
                .background(isActive ? theme.text.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func smallButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.heading(13))
                .frame(width: 36, height: 36)
                .foregroundColor(theme.textDim)
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 22)
    }

    private var voiceTrackingIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(voiceTracker.isListening ? theme.teal : theme.textFaint)
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
                .foregroundColor(voiceTracker.isListening ? theme.teal : theme.textFaint)
        }
        .padding(.horizontal, 4)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = [5, 11, 8, 13][index]
        let boost = CGFloat(voiceTracker.micLevel) * 10
        return min(base + boost, 18)
    }

    private var recordButton: some View {
        Button {
            recorder.isRecording ? recorder.stopRecording() : recorder.startRecording()
        } label: {
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
                if recorder.isRecording {
                    Text(recorder.elapsedTimeText)
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(theme.text)
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
    }
}
