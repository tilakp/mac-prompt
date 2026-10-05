//
//  TeleprompterEngineTests.swift
//  mac-promptTests
//
//  Replaces the old ContentViewTests, which exercised the same scroll-clamping and
//  play/pause behavior directly on ContentView before that logic moved into
//  TeleprompterEngine.
//

import XCTest
@testable import mac_prompt

@MainActor
final class TeleprompterEngineTests: XCTestCase {
    func testInitialState() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        XCTAssertEqual(engine.scrollOffset, 0)
        XCTAssertEqual(engine.speedMultiplier, 1.0)
        XCTAssertFalse(engine.mirrored)
    }

    func testPauseAndResumeScrolling() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.start()
        XCTAssertTrue(engine.isPlaying)
        engine.stop()
        XCTAssertFalse(engine.isPlaying)
        engine.togglePlayPause()
        XCTAssertTrue(engine.isPlaying)
        engine.stop()
    }

    func testScrollOffsetClamp() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        engine.scrollOffset = -1000
        engine.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        // minOffset = availableHeight/2 - textHeight/2 = 100 - 200 = -100.
        XCTAssertEqual(engine.scrollOffset, -100)
    }

    func testResetToStartPlacesTextTopAtReadingLine() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        engine.resetToStart()
        // maxOffset = availableHeight/2 + textHeight/2 = 100 + 200 = 300: the text's
        // own top edge (scrollOffset - textHeight/2) then sits at availableHeight/2,
        // the reading line, with nothing scrolled past it yet.
        XCTAssertEqual(engine.scrollOffset, 300)
        XCTAssertEqual(engine.scrollOffset - 400 / 2, 200 / 2)
    }

    func testMinOffsetPlacesTextBottomAtReadingLine() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        // The text's bottom edge (scrollOffset + textHeight/2) at minOffset should
        // land exactly on the reading line too — the whole script has scrolled
        // through it exactly once by the time scrolling finishes.
        XCTAssertEqual(engine.minOffset + 400 / 2, 200 / 2)
    }

    func testAdvanceMovesOffsetUpwardWhilePlaying() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometryForTest(textHeight: 4000, availableHeight: 400)
        engine.wordCount = 500
        engine.scrollOffset = 200
        engine.start()
        engine.advance(by: 1)
        XCTAssertLessThan(engine.scrollOffset, 200)
        engine.stop()
    }

    func testAdvanceDoesNothingWhilePaused() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometryForTest(textHeight: 4000, availableHeight: 400)
        engine.scrollOffset = 200
        engine.stop()
        engine.advance(by: 1)
        XCTAssertEqual(engine.scrollOffset, 200)
    }

    func testFirstMeasurementStartsAtTopOfScript() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        // The empty placeholder measures 0 high; the real text then loads.
        engine.updateGeometryForTest(textHeight: 0, availableHeight: 200)
        engine.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        XCTAssertEqual(engine.scrollOffset, engine.maxOffset)
    }

    func testReflowKeepsReadingProgress() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        // maxOffset = 300, so 200 is 100pt (a quarter of the text) past the start.
        engine.scrollOffset = 200
        // Bigger font: the text doubles in height. A quarter of 800pt past the new start.
        engine.updateGeometryForTest(textHeight: 800, availableHeight: 200)
        XCTAssertEqual(engine.maxOffset - engine.scrollOffset, 200)
        // Taller window: progress stays a quarter.
        engine.updateGeometryForTest(textHeight: 800, availableHeight: 600)
        XCTAssertEqual(engine.maxOffset - engine.scrollOffset, 200)
    }

    func testFullScriptScrollsInItsEstimatedDuration() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.wordCount = 300 // 2 minutes at 150 wpm
        engine.updateGeometryForTest(textHeight: 1200, availableHeight: 400)
        XCTAssertEqual(engine.pointsPerSecond, 1200 / 120, accuracy: 0.0001)
        // Same words in a wider window wrap to half the height: half the speed, same time.
        engine.updateGeometryForTest(textHeight: 600, availableHeight: 400)
        XCTAssertEqual(engine.pointsPerSecond, 600 / 120, accuracy: 0.0001)
        engine.adjustSpeedMultiplier(by: 0.5)
        XCTAssertEqual(engine.pointsPerSecond, 600 / 120 * 1.5, accuracy: 0.0001)
    }

    func testEmptyScriptDoesNotScroll() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        XCTAssertEqual(engine.pointsPerSecond, 0)
    }

    func testSpeedMultiplierIsClamped() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.adjustSpeedMultiplier(by: 10)
        XCTAssertEqual(engine.speedMultiplier, TeleprompterEngine.speedMultiplierRange.upperBound)
        engine.adjustSpeedMultiplier(by: -10)
        XCTAssertEqual(engine.speedMultiplier, TeleprompterEngine.speedMultiplierRange.lowerBound)
    }
}
