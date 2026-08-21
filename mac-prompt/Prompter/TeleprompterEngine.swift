//
//  TeleprompterEngine.swift
//  mac-prompt
//
//  Generalized from the original ContentView's startScrolling/stopScrolling/
//  updateGeometry scroll-clamping logic, plus a speed multiplier the control bar and
//  VoiceTracker can both drive. `advance(by:)` is exposed directly so unit tests can
//  verify the scrolling math without waiting on a real Timer.

import Foundation

@MainActor
final class TeleprompterEngine: ObservableObject {
    @Published var scrollOffset: CGFloat = 0
    /// False until `start()` actually runs. If a Prompter session never starts
    /// scrolling (e.g. its script failed to load), the control bar's play/pause icon
    /// must reflect that nothing is running rather than defaulting to "playing".
    @Published var isPlaying: Bool = false
    @Published var speedMultiplier: Double = 1.0
    @Published var fontSize: CGFloat
    @Published var mirrored: Bool = false

    var baseWPM: Int
    var lineSpacing: CGFloat

    private(set) var availableHeight: CGFloat = 0
    private(set) var textHeight: CGFloat = 0
    private var timer: Timer?
    private let tickInterval: TimeInterval = 0.008

    static let speedMultiplierRange: ClosedRange<Double> = 0.5...2.0

    init(baseWPM: Int, fontSize: CGFloat, lineSpacing: CGFloat) {
        self.baseWPM = baseWPM
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }

    /// Approximate points-per-second for the current words-per-minute pace. Tuned so
    /// the app's 150 wpm default at 48pt body text scrolls at a natural reading speed
    /// (matching the previous hand-tuned default of ~40pt/s).
    var pointsPerSecond: CGFloat {
        CGFloat(baseWPM) * 0.27 * CGFloat(speedMultiplier)
    }

    var speedMultiplierText: String {
        String(format: "%.1f×", speedMultiplier)
    }

    func updateGeometry(availableHeight: CGFloat, textHeight: CGFloat) {
        self.availableHeight = availableHeight
        self.textHeight = textHeight
        clampOffset()
    }

    /// Testable helper mirroring `updateGeometry`, kept for parity with the previous
    /// `ContentView.updateGeometryForTest`.
    func updateGeometryForTest(textHeight: CGFloat, availableHeight: CGFloat) {
        updateGeometry(availableHeight: availableHeight, textHeight: textHeight)
    }

    private func clampOffset() {
        let minOffset = -(textHeight - availableHeight / 2)
        let maxOffset = availableHeight / 2
        scrollOffset = min(max(scrollOffset, minOffset), maxOffset)
    }

    func start() {
        stopTimer()
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.advance(by: self.tickInterval) }
        }
    }

    func stop() {
        stopTimer()
        isPlaying = false
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func togglePlayPause() {
        isPlaying ? stop() : start()
    }

    /// Advances the scroll offset by one tick. Exposed directly for unit tests.
    func advance(by interval: TimeInterval) {
        guard isPlaying else { return }
        let minOffset = -(textHeight - availableHeight / 2)
        let maxOffset = availableHeight / 2
        let next = scrollOffset - pointsPerSecond * CGFloat(interval)
        scrollOffset = min(max(next, minOffset), maxOffset)
    }

    func adjustSpeedMultiplier(by delta: Double) {
        speedMultiplier = min(max(speedMultiplier + delta, Self.speedMultiplierRange.lowerBound), Self.speedMultiplierRange.upperBound)
    }

    func adjustFontSize(by delta: CGFloat) {
        fontSize = max(18, fontSize + delta)
    }
}
