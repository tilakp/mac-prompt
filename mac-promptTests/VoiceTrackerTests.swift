//
//  VoiceTrackerTests.swift
//  mac-promptTests
//

import XCTest
@testable import mac_prompt

final class VoiceTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    func testWPMNeedsTwoSecondsOfSamples() {
        let samples = [(t0, 0), (t0.addingTimeInterval(1), 3)]
        XCTAssertNil(VoiceTracker.windowedWPM(samples: samples))
    }

    func testWPMUsesWordsAddedOverTheWindow() {
        // 20 words in 10 seconds = 120 wpm, whatever the count was before the window.
        let samples = [(t0, 100), (t0.addingTimeInterval(10), 120)]
        XCTAssertEqual(VoiceTracker.windowedWPM(samples: samples)!, 120, accuracy: 0.0001)
    }

    func testWPMIsNeverNegative() {
        // A partial result can revise the transcript down to fewer words.
        let samples = [(t0, 30), (t0.addingTimeInterval(5), 25)]
        XCTAssertEqual(VoiceTracker.windowedWPM(samples: samples), 0)
    }

    func testTargetKeepsTheManualOffset() {
        // Reading at the script's pace, after the user asked for 0.2 faster.
        XCTAssertEqual(VoiceTracker.targetMultiplier(wpm: 150, baseWPM: 150, manualOffset: 0.2), 1.2, accuracy: 0.0001)
        XCTAssertEqual(VoiceTracker.targetMultiplier(wpm: 600, baseWPM: 150, manualOffset: 0.2), 2.0, accuracy: 0.0001)
    }

    func testSmoothingDependsOnTimeNotOnCallbackCount() {
        let d = 0.035
        // One callback after 0.4 s must move as far as two callbacks 0.2 s apart.
        let one = VoiceTracker.smoothingFactor(damping: d, elapsed: 0.4)
        let step = VoiceTracker.smoothingFactor(damping: d, elapsed: 0.2)
        let two = 1 - (1 - step) * (1 - step)
        XCTAssertEqual(one, two, accuracy: 0.000001)
        XCTAssertEqual(step, d, accuracy: 0.000001)
    }
}
