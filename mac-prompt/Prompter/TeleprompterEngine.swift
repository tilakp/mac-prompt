//
//  TeleprompterEngine.swift
//  mac-prompt
//
//  The Prompter's scrolling: play/pause, speed, and the scroll position. A display
//  link calls `advance(by:)` with the real time since the last frame; unit tests call
//  it directly.
//
//  `scrollOffset` is the Y position of the text's center in the Prompter view, for
//  `.position(y:)`. The reading line is the middle of the view, so at `maxOffset` the
//  text's top edge is on the reading line (the start), and at `minOffset` its bottom
//  edge is (the end). `.position` is used because `.offset` would depend on the
//  alignment of the container around the text.
//
//  `@Observable`, so only views that read a property update when it changes:
//  `scrollOffset` changes on every frame, and only the scrolling text reads it.

import AppKit
import Observation

@MainActor
@Observable
final class TeleprompterEngine {
    var scrollOffset: CGFloat = 0
    /// False until `start()` actually runs. If a Prompter session never starts
    /// scrolling (e.g. its script failed to load), the control bar's play/pause icon
    /// must reflect that nothing is running rather than defaulting to "playing".
    var isPlaying: Bool = false
    var speedMultiplier: Double = 1.0
    /// The sum of the user's own speed changes (↑/↓, −/+). Voice tracking aims for its
    /// measured pace plus this offset, so it does not undo what the user asked for.
    @ObservationIgnored private(set) var manualSpeedOffset: Double = 0
    var fontSize: CGFloat
    var mirrored: Bool = false

    var baseWPM: Int
    var lineSpacing: CGFloat
    /// Spoken words in the script (cue tokens excluded), as `Script.wordCount` counts them.
    var wordCount: Int = 0

    private(set) var availableHeight: CGFloat = 0
    private(set) var textHeight: CGFloat = 0
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrameTimestamp: CFTimeInterval?
    /// A view in the Prompter window. Its display link follows the window from screen
    /// to screen; a link from `NSScreen.main` stays on the first screen, which judders
    /// at a different refresh rate and stops if that screen is disconnected.
    @ObservationIgnored private weak var displayLinkView: NSView?

    nonisolated static let speedMultiplierRange: ClosedRange<Double> = 0.5...2.0

    init(baseWPM: Int, fontSize: CGFloat, lineSpacing: CGFloat) {
        self.baseWPM = baseWPM
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }

    /// The speed that scrolls the full text height past the reading line in the time
    /// `wordCount` words take at `baseWPM` × `speedMultiplier`. It comes from the
    /// measured text height, so the pace stays true at every font size and window
    /// width (a wider window holds more words per line, so it must scroll slower).
    var pointsPerSecond: CGFloat {
        guard wordCount > 0 else { return 0 }
        let wordsPerSecond = Double(baseWPM) * speedMultiplier / 60
        return textHeight * CGFloat(wordsPerSecond / Double(wordCount))
    }

    var speedMultiplierText: String {
        String(format: "%.1f×", speedMultiplier)
    }

    /// Text's top edge at the reading line: the furthest-down (most delayed) position.
    var maxOffset: CGFloat { availableHeight / 2 + textHeight / 2 }
    /// Text's bottom edge at the reading line: the furthest-up (fully read) position.
    var minOffset: CGFloat { availableHeight / 2 - textHeight / 2 }

    /// Keeps the reader at the same fraction of the script when the text reflows (font
    /// size, window size, or a live edit), not at the same Y position, which would
    /// show a different part of the script. With no text before (the empty placeholder
    /// that shows until the script loads), the progress is 0: the start of the script.
    func updateGeometry(availableHeight: CGFloat, textHeight: CGFloat) {
        let oldTextHeight = self.textHeight
        let progress = oldTextHeight > 0 ? (maxOffset - scrollOffset) / oldTextHeight : 0
        self.availableHeight = availableHeight
        self.textHeight = textHeight
        scrollOffset = maxOffset - progress * textHeight
        clampOffset()
    }

    private func clampOffset() {
        scrollOffset = min(max(scrollOffset, minOffset), maxOffset)
    }

    /// Jumps to the very start of the script (text's top edge at the reading line).
    /// Called on the first geometry measurement; later measurements keep the reader's
    /// progress instead (see `updateGeometry`).
    func resetToStart() {
        scrollOffset = maxOffset
    }

    /// Uses `view`'s display link from now on, and moves a running link to it.
    func attach(to view: NSView) {
        displayLinkView = view
        if isPlaying { start() }
    }

    func start() {
        stopDisplayLink()
        isPlaying = true
        // A display link fires once per screen refresh, so the text moves exactly once
        // per frame. `.common` mode keeps it running while a menu or control is held.
        let target = DisplayLinkTarget { [weak self] timestamp in self?.step(timestamp: timestamp) }
        let selector = #selector(DisplayLinkTarget.step(_:))
        // The screen link is only for when no view is attached yet (and for unit tests).
        let link = displayLinkView?.displayLink(target: target, selector: selector)
            ?? (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: target, selector: selector)
        link?.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        stopDisplayLink()
        isPlaying = false
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = nil
    }

    func togglePlayPause() {
        isPlaying ? stop() : start()
    }

    /// Advances by the real time since the previous frame, so a dropped or late frame
    /// does not slow the scroll down.
    private func step(timestamp: CFTimeInterval) {
        defer { lastFrameTimestamp = timestamp }
        guard let lastFrameTimestamp else { return }
        // Cap the step so a long stall (e.g. a blocked main thread) cannot jump the text.
        advance(by: min(timestamp - lastFrameTimestamp, 0.1))
    }

    /// Advances the scroll offset by one tick. Exposed directly for unit tests.
    func advance(by interval: TimeInterval) {
        guard isPlaying else { return }
        let next = min(max(scrollOffset - pointsPerSecond * CGFloat(interval), minOffset), maxOffset)
        // Every write notifies observers, even of an equal value; at the end of the
        // script that would re-render the text on every frame for nothing.
        guard next != scrollOffset else { return }
        scrollOffset = next
    }

    /// A speed change by the user. VoiceTracker sets `speedMultiplier` directly.
    func adjustSpeedMultiplier(by delta: Double) {
        let old = speedMultiplier
        speedMultiplier = min(max(speedMultiplier + delta, Self.speedMultiplierRange.lowerBound), Self.speedMultiplierRange.upperBound)
        manualSpeedOffset += speedMultiplier - old
    }

    func adjustFontSize(by delta: CGFloat) {
        fontSize = max(18, fontSize + delta)
    }
}

/// `CADisplayLink` needs an Objective-C target and keeps a strong reference to it;
/// this small object holds only a weak path back to the engine.
private final class DisplayLinkTarget: NSObject {
    private let onFrame: @MainActor (CFTimeInterval) -> Void

    init(onFrame: @escaping @MainActor (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
    }

    @objc func step(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        // The link is added to the main run loop, so this always runs on the main thread.
        MainActor.assumeIsolated { onFrame(timestamp) }
    }
}
