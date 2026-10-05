//
//  TeleprompterEngine.swift
//  mac-prompt
//
//  Generalized from the original ContentView's startScrolling/stopScrolling/
//  updateGeometry scroll-clamping logic, plus a speed multiplier the control bar and
//  VoiceTracker can both drive. `advance(by:)` is exposed directly so unit tests can
//  verify the scrolling math without waiting on a real display link.
//
//  `scrollOffset` is the Y coordinate — in the Prompter view's own coordinate space —
//  of the scrolling text block's vertical CENTER, meant to be applied via
//  `.position(y: scrollOffset)` rather than `.offset(y:)`. `.position()` places a
//  view's center at an exact, unambiguous point, which is what makes the two bounds
//  below reason about cleanly: at `maxOffset` the text's own TOP edge sits at the
//  reading line (vertical center of the window, where the reading-guide band is drawn)
//  so the very first line is immediately readable there; at `minOffset` the text's
//  BOTTOM edge has reached that same line, so the whole script has scrolled through it
//  exactly once. (`.offset(y:)` was tried first and abandoned — its effective starting
//  position depends on the exact default alignment of whatever ancestor container
//  wraps the text, which turned out to be too easy to get subtly wrong.)
//
//  `@Observable` (not `ObservableObject`) so a view re-renders only when a property it
//  actually reads changes: `scrollOffset` changes every frame while playing, and only
//  the scrolling text reads it.

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

    static let speedMultiplierRange: ClosedRange<Double> = 0.5...2.0

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

    /// Testable helper mirroring `updateGeometry`, kept for parity with the previous
    /// `ContentView.updateGeometryForTest`.
    func updateGeometryForTest(textHeight: CGFloat, availableHeight: CGFloat) {
        updateGeometry(availableHeight: availableHeight, textHeight: textHeight)
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

    func start() {
        stopDisplayLink()
        isPlaying = true
        // A display link fires once per screen refresh, so the text moves exactly once
        // per frame. `.common` mode keeps it running while a menu or control is held.
        let target = DisplayLinkTarget { [weak self] timestamp in self?.step(timestamp: timestamp) }
        let link = (NSScreen.main ?? NSScreen.screens.first)?
            .displayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
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

    func adjustSpeedMultiplier(by delta: Double) {
        speedMultiplier = min(max(speedMultiplier + delta, Self.speedMultiplierRange.lowerBound), Self.speedMultiplierRange.upperBound)
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
