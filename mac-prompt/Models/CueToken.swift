//
//  CueToken.swift
//  mac-prompt
//
//  The cues the editor toolbar inserts. `ScriptMarkup.cueRegex` recognizes them.

enum CueToken {
    case pause, emphasis, faster, slower

    var text: String {
        switch self {
        case .pause: return "[PAUSE]"
        case .emphasis: return "[EMPHASIS]"
        case .faster: return "»» FASTER"
        case .slower: return "«« SLOWER"
        }
    }
}
