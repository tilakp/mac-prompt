//
//  AppSettings.swift
//  mac-prompt
//

import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable, Hashable {
    case dark, light, auto
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .auto: return "Auto"
        }
    }
}

enum PrompterFontSize: String, CaseIterable, Identifiable, Hashable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    var points: CGFloat {
        switch self {
        case .small: return 34
        case .medium: return 48
        case .large: return 64
        }
    }
}

enum VoiceTrackingSensitivity: String, CaseIterable, Identifiable, Hashable {
    case low, balanced, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: return "Low"
        case .balanced: return "Balanced"
        case .high: return "High"
        }
    }
    /// Fraction of the measured speed gap corrected per engine tick. Higher = snappier,
    /// more prone to overshoot on a noisy mic signal.
    var dampingFactor: Double {
        switch self {
        case .low: return 0.015
        case .balanced: return 0.035
        case .high: return 0.07
        }
    }
}

/// Centralized `@AppStorage` keys, read/written from Settings and consumed as defaults
/// when new scripts are created or Prompter sessions start.
enum AppSettingsKey {
    static let defaultWPM = "defaultWPM"
    static let defaultPrompterFontSize = "defaultPrompterFontSize"
    static let theme = "themePreference"
    static let voiceTrackingEnabled = "voiceTrackingEnabled"
    static let voiceTrackingSensitivity = "voiceTrackingSensitivity"
    static let cameraPassthroughEnabled = "cameraPassthroughEnabled"
    static let cameraDeviceID = "cameraDeviceID"
}

@MainActor
struct AppSettingsDefaults {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            AppSettingsKey.defaultWPM: 150,
            AppSettingsKey.defaultPrompterFontSize: PrompterFontSize.medium.rawValue,
            AppSettingsKey.theme: ThemePreference.dark.rawValue,
            AppSettingsKey.voiceTrackingEnabled: true,
            AppSettingsKey.voiceTrackingSensitivity: VoiceTrackingSensitivity.balanced.rawValue,
            AppSettingsKey.cameraPassthroughEnabled: true,
        ])
    }
}
