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

    func testCueWithoutSpacesDoesNotJoinWords() {
        XCTAssertEqual(Script(body: "Hello[PAUSE]world").wordCount, 2)
    }

    func testSnippetCutsLongBodiesAt140Characters() {
        let script = Script(body: String(repeating: "a", count: 200))
        XCTAssertEqual(script.snippet, String(repeating: "a", count: 140) + "…")
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
        // A "*" that is not part of bold or italic markup must stay in the text.
        let text = ScriptMarkup.plainText(from: "5 * 3 = 15, and **this** is bold.")
        XCTAssertEqual(text, "5 * 3 = 15, and this is bold.")
    }

    func testPlainDisplayTextKeepsSpacedAsterisks() {
        // "* 3 *" has spaces inside the markers, so it is arithmetic, not italic markup.
        XCTAssertEqual(ScriptMarkup.plainText(from: "5 * 3 * 2"), "5 * 3 * 2")
        XCTAssertEqual(ScriptMarkup.plainText(from: "a *b* c"), "a b c")
    }

    func testEstimatedDurationFromWordCount() {
        XCTAssertEqual(Script.estimatedDuration(wordCount: 300, wpm: 150), "2:00")
        XCTAssertEqual(Script.estimatedDuration(wordCount: 10, wpm: 0), "10:00")
    }

    func testFormatDuration() {
        XCTAssertEqual(Script.formatDuration(totalSeconds: 65), "1:05")
        XCTAssertEqual(Script.formatDuration(totalSeconds: 5), "0:05")
    }
}

final class ScriptMarkupTests: XCTestCase {
    func testCueRegexMatchesAllTokenForms() {
        let text = "[PAUSE] then [EMPHASIS] then »» FASTER then «« SLOWER"
        let matches = ScriptMarkup.cueRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(matches.count, 4)
    }

    func testCueRegexDoesNotSpanLines() {
        // A cue is one line. "»»" on one line and "FASTER" on the next are two words.
        let text = "»»\n\nFASTER and »» FASTER"
        let matches = ScriptMarkup.cueRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(matches.count, 1)
    }

    func testCueRegexIgnoresPlainBrackets() {
        let text = "This is [not a cue] at all"
        let matches = ScriptMarkup.cueRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertTrue(matches.isEmpty)
    }

    func testBoldRegexMatchesDoubleAsterisks() {
        let text = "This is **bold** text"
        let matches = ScriptMarkup.boldRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(matches.count, 1)
    }

    func testItalicRegexDoesNotMatchInsideBold() {
        let text = "**bold** and *italic*"
        let italicMatches = ScriptMarkup.italicRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        XCTAssertEqual(italicMatches.count, 1)
    }
}

final class CueTextControllerTests: XCTestCase {
    func testWrapKeepsMarkersNextToTheText() {
        XCTAssertEqual(CueTextController.wrap("  hello there ", with: "**"), "  **hello there** ")
        XCTAssertEqual(CueTextController.wrap("   ", with: "*"), "   ")
    }
}
