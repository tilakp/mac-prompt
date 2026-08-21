# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Prompt (product name; Xcode target/module name is still `mac-prompt`) is a macOS teleprompter app built with SwiftUI + SwiftData (`MACOSX_DEPLOYMENT_TARGET` 14.6/15.4, Swift 5.0, sandboxed). It manages a library of scripts across folders, edits them with pacing/cue markup, and reads them back in a full-screen prompter with optional camera passthrough, recording, and mic-driven voice tracking.

## Commands

There is no package manager (SwiftPM/CocoaPods/Carthage) — this is a plain Xcode project (`mac-prompt.xcodeproj`) with no shared `.xcscheme`, so `xcodebuild` uses the auto-generated scheme named after the target: `mac-prompt`. The project uses Xcode 16's `PBXFileSystemSynchronizedRootGroup`, so **new `.swift` files just need to be placed under `mac-prompt/mac-prompt/`** (in the appropriate subfolder) — Xcode picks them up automatically, no pbxproj editing required for source files.

Build:
```sh
xcodebuild -project mac-prompt.xcodeproj -scheme mac-prompt build
```

Run all tests (unit tests in `mac-promptTests`, UI tests in `mac-promptUITests`):
```sh
xcodebuild -project mac-prompt.xcodeproj -scheme mac-prompt test
```

Run a single test:
```sh
xcodebuild -project mac-prompt.xcodeproj -scheme mac-prompt test -only-testing:mac-promptTests/TeleprompterEngineTests/testScrollOffsetClamp
```

Alternatively, open `mac-prompt.xcodeproj` in Xcode and use Cmd+R / Cmd+U.

CI (`.github/workflows/objective-c-xcode.yml`) runs `xcodebuild clean build analyze` against the default scheme on every push/PR to `main`.

Packaging a release DMG (`release.sh`, requires `create-dmg`):
```sh
./release.sh
```
This expects a built `mac-prompt.app` under `./release/` and produces `mac-prompt-Installer.dmg`.

## Architecture

The app is three SwiftUI `Scene`s sharing one SwiftData `ModelContainer` (`mac-prompt/mac_promptApp.swift`):

- A `WindowGroup` opening `Library/LibraryView.swift` — the main window.
- A `WindowGroup(id: "prompter", for: UUID.self)` opening `Prompter/PrompterView.swift`, keyed by a `Script.id`. `EditorView`'s "Start Prompting" button calls `openWindow(id: "prompter", value: script.id)` to open one.
- A `Settings { }` scene opening `Settings/SettingsView.swift` (Cmd+,).

### Data model (`Models/`)

`Script` and `Folder` are SwiftData `@Model` classes (`Models/Script.swift`, `Models/Folder.swift`). A script's body is **plain text** — cue markers (`[PAUSE]`, `[EMPHASIS]`, `»» FASTER`, `«« SLOWER`) and light markdown emphasis (`**bold**`, `*italic*`) are literal substrings parsed at render/highlight time via the shared regexes in `Models/CueToken.swift`, not persisted rich-text attributes. This keeps scripts portable and is why `Script.wordCount`/`snippet`/`estimatedDuration` all strip cue tokens the same way the editor's highlighter matches them. `SmartFolder` (`Models/SmartFolder.swift`) is an unpersisted enum driving the sidebar's built-in Library/Recent/Favorites/Trash sections.

### Library (`Library/`)

`LibraryView` is a `NavigationSplitView`: `SidebarView` (smart folders + user folders) on the left, and on the right either the script grid/list (`ScriptCardView` per script) or — once a script is selected — `EditorView` swapped in as the detail content. There's no separate editor window; opening a script is an in-place detail swap, matching the "Library / ⟨title⟩" breadcrumb in the editor header.

### Editor (`Editor/`)

`EditorView` assembles a breadcrumb/toolbar header, `CueTextView` (the text area), and an inspector column (`ReadingPacePanel`, `AppearancePanel`, `FolderTagsPanel`). `CueTextView` wraps `NSTextView` directly (SwiftUI's `TextEditor` can't do inline syntax highlighting) and re-applies cue/bold/italic attributes via `Models/CueToken`'s regexes on every edit. `CueTextController` lets the formatting toolbar insert/wrap text at the actual cursor position rather than always appending to the end.

### Prompter (`Prompter/`)

- `TeleprompterEngine` — the scroll/play-pause state machine (extracted from what used to be inline in the app's single `ContentView`). `advance(by:)` is exposed directly so unit tests can drive the scrolling math without a real `Timer`.
- `PrompterView` — assembles the camera background (or a plain background, if passthrough is off in Settings), the scrolling text (masked/faded top and bottom), a reading-guide band, and `PrompterControlBar`. The whole composed view (camera + text + guide band) flips via `.scaleEffect(x: -1)` when "Mirror flip" (M) is toggled — for physical teleprompter beam-splitter rigs that need the entire display reversed, not just the camera.
- `CameraPreviewView` — a dumb `NSViewRepresentable` presenting a live `AVCaptureSession`.
- `RecordingController` — owns the `AVCaptureSession` (video + audio input, `AVCaptureMovieFileOutput`) used by both the passthrough preview and recording. Recordings are written into the app's own sandboxed Documents directory — no extra file-picker entitlement needed.
- `VoiceTracker` — see "Voice tracking" below.
- `PrompterKeyCatcherView` — a generalized `NSViewRepresentable` key-event catcher (Space/↑/↓/R/M/Esc), the same first-responder-capture technique the original single-file app used for just the space bar.

**Voice tracking is intentionally scoped down** from what "listens and matches your pace" might suggest: it does not attempt word-level alignment (scrubbing the scroll position to the exact word being spoken). `VoiceTracker` runs live on-device `SFSpeechRecognizer` transcription, measures actual words-per-minute since the current recognition session started, and smoothly nudges `TeleprompterEngine.speedMultiplier` toward that measured rate (damping controlled by the Settings sensitivity level). Live recognition sessions time out after roughly a minute; `VoiceTracker` transparently restarts them.

### Settings (`Settings/`)

`AppSettings.swift` centralizes all `@AppStorage` keys and the enums backing them (`ThemePreference`, `PrompterFontSize`, `VoiceTrackingSensitivity`). `SettingsView.swift` is a `TabView` with General / Reading & Display / Voice Tracking / Camera & PiP / Shortcuts tabs.

### Design system (`DesignSystem/Theme.swift`)

A native adaptation of a violet/coral dark palette (originally specced with Google Fonts Space Grotesk/Plus Jakarta Sans and OKLCH colors): SwiftUI `Color` tokens with light/dark variants, plus shared button styles and view modifiers (`GradientButtonStyle`, `NavItemStyle`, `.glassPill()`, `.cardBackground()`, `PillSegmentedControl`). Fonts use the system font's `.rounded` design instead of bundling third-party font files, to keep the app dependency-free. `theme` is read via `@Environment(\.theme)`, populated once per `Scene` root by the `.themed()` modifier (applied in `mac_promptApp.swift`) from `@Environment(\.colorScheme)` — don't call `.themed()` deeper in the tree expecting it to affect that same view's own top-level reads, since a view's own `@Environment` reads reflect what its *ancestors* set, not modifiers it applies to its own children.

### Entitlements & permissions

`mac-prompt/mac_prompt.entitlements` has sandbox + file read-write (for the old load/save-script panels, no longer wired to the editor but still declared) plus `com.apple.security.device.camera` and `com.apple.security.device.microphone` for Prompter's camera passthrough, recording, and voice tracking. Usage-description strings (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) are `INFOPLIST_KEY_*` build settings in `project.pbxproj` (this project has `GENERATE_INFOPLIST_FILE = YES` and no physical Info.plist — see the `mac-prompt` target's Debug/Release build settings for the existing key pattern before adding more).

## Repo layout gotcha

`mac-prompt/` (the source directory) has its own **separate, unrelated nested `.git`** directory with a different commit history than the outer repo, both pointing at the same GitHub remote. It's a leftover, not a submodule. Running git commands from inside `mac-prompt/mac-prompt/` will operate on that inner repo instead of the outer one — stay at the repo root (where this file lives) for git operations.
