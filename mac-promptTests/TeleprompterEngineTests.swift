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

    func testSpeedMultiplierIsClamped() {
        let engine = TeleprompterEngine(baseWPM: 150, fontSize: 48, lineSpacing: 12)
        engine.adjustSpeedMultiplier(by: 10)
        XCTAssertEqual(engine.speedMultiplier, TeleprompterEngine.speedMultiplierRange.upperBound)
        engine.adjustSpeedMultiplier(by: -10)
        XCTAssertEqual(engine.speedMultiplier, TeleprompterEngine.speedMultiplierRange.lowerBound)
    }
}
