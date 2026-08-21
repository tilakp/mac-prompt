//
//  CueToken.swift
//  mac-prompt
//
//  Inline markup recognized in a script's plain-text body. Cue tokens are literal
//  bracketed substrings (e.g. "[PAUSE]") rather than persisted rich-text attributes,
//  so scripts stay portable plain text; both the editor's syntax highlighting and the
//  library snippet/word-count logic parse them with the same regexes.

import Foundation

enum CueToken: String, CaseIterable {
    case pause = "PAUSE"
    case emphasis = "EMPHASIS"
    case faster = "FASTER"
    case slower = "SLOWER"

    var displayText: String {
        switch self {
        case .pause: return "[PAUSE]"
        case .emphasis: return "[EMPHASIS]"
        case .faster: return "»» FASTER"
        case .slower: return "«« SLOWER"
        }
    }

    /// The exact literal token inserted into a script's body by the editor toolbar.
    var insertionText: String { displayText }

    static let cueRegex: NSRegularExpression = {
        // Matches "[PAUSE]", "[EMPHASIS]", "»» FASTER", "«« SLOWER".
        let pattern = #"\[(PAUSE|EMPHASIS)\]|»»\s*FASTER|««\s*SLOWER"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    static let boldRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    }()

    static let italicRegex: NSRegularExpression = {
        // Single-asterisk emphasis that isn't part of a "**bold**" run.
        try! NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    }()

    /// All regexes whose matches should be removed entirely when computing word
    /// counts / snippets (cue tokens carry no spoken words of their own).
    static let allRegexes: [NSRegularExpression] = [cueRegex]
}
