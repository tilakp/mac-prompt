//
//  SettingsView.swift
//  mac-prompt
//

import AVFoundation
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ReadingDisplaySettingsTab()
                .tabItem { Label("Reading & Display", systemImage: "textformat") }
            VoiceTrackingSettingsTab()
                .tabItem { Label("Voice Tracking", systemImage: "waveform") }
            CameraSettingsTab()
                .tabItem { Label("Camera & PiP", systemImage: "camera") }
            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .themed()
        .frame(width: 560, height: 440)
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.heading(14.5))
                .foregroundColor(theme.text)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsRow<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let label: String
    var help: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundColor(theme.textDim)
                if let help {
                    Text(help).font(.system(size: 11)).foregroundColor(theme.textFaint).frame(maxWidth: 320, alignment: .leading)
                }
            }
            Spacer()
            trailing
        }
    }
}

private struct GeneralSettingsTab: View {
    @Environment(\.theme) private var theme
    @AppStorage(AppSettingsKey.theme) private var themeRaw = ThemePreference.dark.rawValue

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Appearance", systemImage: "circle.righthalf.filled") {
                SettingsRow(label: "Theme") {
                    Picker("", selection: Binding(
                        get: { ThemePreference(rawValue: themeRaw) ?? .dark },
                        set: { themeRaw = $0.rawValue }
                    )) {
                        ForEach(ThemePreference.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            SettingsSection(title: "About", systemImage: "info.circle") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt").font(.system(size: 13, weight: .semibold)).foregroundColor(theme.text)
                    Text("An open-source teleprompter for macOS.").font(.system(size: 11.5)).foregroundColor(theme.textFaint)
                }
            }
        }
        .padding(20)
        }
    }
}

private struct ReadingDisplaySettingsTab: View {
    @AppStorage(AppSettingsKey.defaultWPM) private var defaultWPM = 150
    @AppStorage(AppSettingsKey.defaultPrompterFontSize) private var defaultFontSizeRaw = PrompterFontSize.medium.rawValue

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Reading & Display", systemImage: "textformat") {
                SettingsRow(label: "Default scroll speed", help: "Words per minute new scripts start at.") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { Double(defaultWPM) }, set: { defaultWPM = Int($0) }), in: 80...240)
                            .frame(width: 180)
                        Text("\(defaultWPM) wpm").font(.system(size: 12, weight: .bold)).frame(width: 60, alignment: .trailing)
                    }
                }
                SettingsRow(label: "Prompter font size") {
                    Picker("", selection: Binding(
                        get: { PrompterFontSize(rawValue: defaultFontSizeRaw) ?? .medium },
                        set: { defaultFontSizeRaw = $0.rawValue }
                    )) {
                        ForEach(PrompterFontSize.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
        }
        .padding(20)
        }
    }
}

private struct VoiceTrackingSettingsTab: View {
    @AppStorage(AppSettingsKey.voiceTrackingEnabled) private var enabled = true
    @AppStorage(AppSettingsKey.voiceTrackingSensitivity) private var sensitivityRaw = VoiceTrackingSensitivity.balanced.rawValue

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Voice Tracking", systemImage: "waveform") {
                SettingsRow(
                    label: "Auto-adjust speed to my voice",
                    help: "Listens through the mic and nudges scroll speed toward your measured speaking pace as you read. It does not jump to specific words — it smooths toward your overall rate."
                ) {
                    Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(label: "Sensitivity") {
                    Picker("", selection: Binding(
                        get: { VoiceTrackingSensitivity(rawValue: sensitivityRaw) ?? .balanced },
                        set: { sensitivityRaw = $0.rawValue }
                    )) {
                        ForEach(VoiceTrackingSensitivity.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
            }
        }
        .padding(20)
        }
    }
}

private struct CameraSettingsTab: View {
    @AppStorage(AppSettingsKey.cameraPassthroughEnabled) private var cameraEnabled = true
    @AppStorage(AppSettingsKey.cameraDeviceID) private var cameraDeviceID = ""

    private var availableCameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Camera & PiP", systemImage: "camera") {
                SettingsRow(
                    label: "Camera passthrough",
                    help: "Show a live camera feed behind the scrolling script in Prompter mode, so you can record yourself reading."
                ) {
                    Toggle("", isOn: $cameraEnabled).labelsHidden().toggleStyle(.switch)
                }
                SettingsRow(label: "Camera source") {
                    Picker("", selection: $cameraDeviceID) {
                        Text("System Default").tag("")
                        ForEach(availableCameras, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                .disabled(!cameraEnabled)
                .opacity(cameraEnabled ? 1 : 0.5)
            }
        }
        .padding(20)
        }
    }
}

private struct ShortcutsSettingsTab: View {
    @Environment(\.theme) private var theme

    private let shortcuts: [(String, String)] = [
        ("Play / Pause", "Space"),
        ("Speed up", "↑"),
        ("Speed down", "↓"),
        ("Start / Stop recording", "R"),
        ("Mirror flip", "M"),
        ("Exit prompter", "Esc"),
    ]

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Keyboard Shortcuts", systemImage: "keyboard") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(shortcuts, id: \.0) { shortcut in
                        HStack {
                            Text(shortcut.0).font(.system(size: 12, weight: .semibold)).foregroundColor(theme.textDim)
                            Spacer()
                            Text(shortcut.1)
                                .font(.heading(11))
                                .foregroundColor(theme.textDim)
                                .padding(.horizontal, 6)
                                .frame(minWidth: 24, minHeight: 20)
                                .background(theme.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(theme.border, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(20)
        }
    }
}
