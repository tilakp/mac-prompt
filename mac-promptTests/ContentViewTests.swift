//
//  ContentViewTests.swift
//  mac-promptTests
//
//  Created by Cascade AI on 4/19/25.
//

import XCTest
@testable import mac_prompt

final class ContentViewTests: XCTestCase {
    func testInitialState() throws {
        let view = ContentView()
        // The default state should be edit mode
        XCTAssertTrue(view.isEditMode)
        // The prompt text should not be empty
        XCTAssertFalse(view.promptText.isEmpty)
        // The text should be white on black
        XCTAssertEqual(view.bgColor, .black)
        XCTAssertEqual(view.textColor, .white)
    }

    func testPauseAndResumeScrolling() throws {
        var view = ContentView()
        // Start in playing state
        view.isPlaying = true
        view.stopScrolling()
        XCTAssertFalse(view.isPlaying)
        view.isPlaying = false
        view.startScrolling()
        XCTAssertTrue(view.isPlaying)
    }

    func testScrollOffsetClamp() throws {
        var view = ContentView()
        view.availableHeight = 200
        view.textHeight = 400
        view.scrollOffset = -1000
        view.updateGeometryForTest(textHeight: 400, availableHeight: 200)
        // Should clamp to min offset
        let minOffset = -(view.textHeight - view.availableHeight / 2)
        XCTAssertEqual(view.scrollOffset, minOffset)
    }
}
