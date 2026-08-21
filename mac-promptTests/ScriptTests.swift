//
//  ScriptTests.swift
//  mac-promptTests
//

import XCTest
@testable import mac_prompt

final class ScriptTests: XCTestCase {
    func testWordCountIgnoresCueTokens() {
        let script = Script(body: "Hello there [PAUSE] friend, welcome »» FASTER to the show.")
        // "Hello there friend, welcome to the show." = 7 words.
        XCTAssertEqual(script.wordCount, 7)
    }

    func testWordCountOfEmptyBody() {
        let script = Script(body: "")
        XCTAssertEqual(script.wordCount, 0)
    }

    func testEstimatedDurationAtGivenPace() {
        let script = Script(body: Array(repeating: "word", count: 150).joined(separator: " "))
        XCTAssertEqual(script.estimatedDuration(at: 150), "1:00")
    }

    func testEstimatedDurationUsesTargetWPMByDefault() {
        let script = Script(body: Array(repeating: "word", count: 300).joined(separator: " "), targetWPM: 150)
        XCTAssertEqual(script.estimatedDuration, "2:00")
    }

    func testSnippetStripsCueTokensAndMarkdown() {
        let script = Script(body: "**Big** opener. [EMPHASIS] Then *quietly* trail off.")
        XCTAssertFalse(script.snippet.contains("["))
        XCTAssertFalse(script.snippet.contains("*"))
        XCTAssertTrue(script.snippet.contains("Big opener"))
    }

    func testPlainDisplayTextPreservesUnmatchedAsterisks() {
        // A lone/unpaired "*" isn't matched bold/italic markup, so it must survive —
        // regression test for a bug where every literal "*" was deleted outright.
        let text = Script.plainDisplayText(from: "5 * 3 = 15, and **this** is bold.")
        XCTAssertEqual(text, "5 * 3 = 15, and this is bold.")
    }

    func testFormatDuration() {
        XCTAssertEqual(Script.formatDuration(totalSeconds: 65), "1:05")
        XCTAssertEqual(Script.formatDuration(totalSeconds: 5), "0:05")
    }
}

final class CueTokenTests: XCTestCase {
    func testCueRegexMatchesAllTokenForms() {
        let text = "[PAUSE] then [EMPHASIS] then »» FASTER then «« SLOWER"
        let matches = CueToken.cueRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(matches.count, 4)
    }

    func testCueRegexIgnoresPlainBrackets() {
        let text = "This is [not a cue] at all"
        let matches = CueToken.cueRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertTrue(matches.isEmpty)
    }

    func testBoldRegexMatchesDoubleAsterisks() {
        let text = "This is **bold** text"
        let matches = CueToken.boldRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(matches.count, 1)
    }

    func testItalicRegexDoesNotMatchInsideBold() {
        let text = "**bold** and *italic*"
        let italicMatches = CueToken.italicRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(italicMatches.count, 1)
    }
}
