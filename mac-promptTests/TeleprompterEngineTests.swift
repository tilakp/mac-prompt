//
//  TeleprompterEngineTests.swift
//  mac-promptTests
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
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        engine.scrollOffset = -1000
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        // minOffset = availableHeight/2 - textHeight/2 = 100 - 200 = -100.
        XCTAssertEqual(engine.scrollOffset, -100)
    }

    func testResetToStartPlacesTextTopAtReadingLine() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        engine.resetToStart()
        // maxOffset = availableHeight/2 + textHeight/2 = 100 + 200 = 300: the text's
        // own top edge (scrollOffset - textHeight/2) then sits at availableHeight/2,
        // the reading line, with nothing scrolled past it yet.
        XCTAssertEqual(engine.scrollOffset, 300)
        XCTAssertEqual(engine.scrollOffset - 400 / 2, 200 / 2)
    }

    func testMinOffsetPlacesTextBottomAtReadingLine() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        // At minOffset the text's bottom edge (scrollOffset + textHeight/2) is on the
        // reading line: the whole script has scrolled past it exactly once.
        XCTAssertEqual(engine.minOffset + 400 / 2, 200 / 2)
    }

    func testAdvanceMovesOffsetUpwardWhilePlaying() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometry(availableHeight: 400, textHeight: 4000)
        engine.wordCount = 500
        engine.scrollOffset = 200
        engine.start()
        engine.advance(by: 1)
        XCTAssertLessThan(engine.scrollOffset, 200)
        engine.stop()
    }

    func testAdvanceDoesNothingWhilePaused() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometry(availableHeight: 400, textHeight: 4000)
        engine.scrollOffset = 200
        engine.stop()
        engine.advance(by: 1)
        XCTAssertEqual(engine.scrollOffset, 200)
    }

    func testFirstMeasurementStartsAtTopOfScript() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        // The empty placeholder measures 0 high; the real text then loads.
        engine.updateGeometry(availableHeight: 200, textHeight: 0)
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        XCTAssertEqual(engine.scrollOffset, engine.maxOffset)
    }

    func testReflowKeepsReadingProgress() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        // maxOffset = 300, so 200 is 100pt (a quarter of the text) past the start.
        engine.scrollOffset = 200
        // Bigger font: the text doubles in height. A quarter of 800pt past the new start.
        engine.updateGeometry(availableHeight: 200, textHeight: 800)
        XCTAssertEqual(engine.maxOffset - engine.scrollOffset, 200)
        // Taller window: progress stays a quarter.
        engine.updateGeometry(availableHeight: 600, textHeight: 800)
        XCTAssertEqual(engine.maxOffset - engine.scrollOffset, 200)
    }

    func testFullScriptScrollsInItsEstimatedDuration() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.wordCount = 300 // 2 minutes at 150 wpm
        engine.updateGeometry(availableHeight: 400, textHeight: 1200)
        XCTAssertEqual(engine.pointsPerSecond, 1200 / 120, accuracy: 0.0001)
        // Same words in a wider window wrap to half the height: half the speed, same time.
        engine.updateGeometry(availableHeight: 400, textHeight: 600)
        XCTAssertEqual(engine.pointsPerSecond, 600 / 120, accuracy: 0.0001)
        engine.adjustSpeedMultiplier(by: 0.5)
        XCTAssertEqual(engine.pointsPerSecond, 600 / 120 * 1.5, accuracy: 0.0001)
    }

    func testEmptyScriptDoesNotScroll() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        XCTAssertEqual(engine.pointsPerSecond, 0)
    }

    func testAdvanceStopsAtTheEndOfTheScript() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.wordCount = 10
        engine.updateGeometry(availableHeight: 200, textHeight: 400)
        engine.start()
        engine.advance(by: 3600)
        XCTAssertEqual(engine.scrollOffset, engine.minOffset)
        engine.stop()
    }

    func testFontSizeHasAMinimum() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 20, lineSpacing: 12)
        engine.adjustFontSize(by: -10)
        XCTAssertEqual(engine.fontSize, 18)
    }

    func testManualSpeedChangesAreKeptAsAnOffset() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.adjustSpeedMultiplier(by: 0.2)
        XCTAssertEqual(engine.manualSpeedOffset, 0.2, accuracy: 0.0001)
        // Only the part of a change that the clamp lets through counts.
        engine.speedMultiplier = 1.9
        engine.adjustSpeedMultiplier(by: 0.5)
        XCTAssertEqual(engine.manualSpeedOffset, 0.3, accuracy: 0.0001)
    }

    func testSpeedMultiplierIsClamped() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.adjustSpeedMultiplier(by: 10)
        XCTAssertEqual(engine.speedMultiplier, TeleprompterEngine.speedMultiplierRange.upperBound)
        engine.adjustSpeedMultiplier(by: -10)
        XCTAssertEqual(engine.speedMultiplier, TeleprompterEngine.speedMultiplierRange.lowerBound)
    }
}
