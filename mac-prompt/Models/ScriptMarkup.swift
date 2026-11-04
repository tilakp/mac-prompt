//
//  ScriptMarkup.swift
//  mac-prompt
//
//  The markup in a script's plain-text body: cue tokens ("[PAUSE]", "»» FASTER") and
//  light emphasis ("**bold**", "*italic*"). The editor's highlighter, the word count
//  and the Prompter all use these regexes, so they always agree. Every pattern matches
//  within one line, so the editor can restyle only the lines that changed.

import Foundation

enum ScriptMarkup {
    static let cueRegex = regex(#"\[(PAUSE|EMPHASIS)\]|»»[ \t]*FASTER|««[ \t]*SLOWER"#)
    static let boldRegex = regex(#"\*\*([^*\n]+)\*\*"#)
    /// Single-asterisk emphasis that is not part of "**bold**". The text must touch both
    /// markers, so arithmetic such as "5 * 3 * 2" is not italic.
    static let italicRegex = regex(#"(?<!\*)\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?!\*)"#)

    /// `text` without cue tokens. Each cue becomes a space, so "Hello[PAUSE]world" is
    /// still two words.
    static func removingCues(from text: String) -> String {
        replacing(cueRegex, in: text, with: " ")
    }

    /// `text` as plain prose: no cues, and bold or italic text without its markers.
    /// A `*` that is not matched markup (e.g. "5 * 3 = 15") stays.
    static func plainText(from text: String) -> String {
        let withoutCues = removingCues(from: text)
        return replacing(italicRegex, in: replacing(boldRegex, in: withoutCues, with: "$1"), with: "$1")
    }

    private static func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants, so a failure is a programming error.
        try! NSRegularExpression(pattern: pattern)
    }
}
