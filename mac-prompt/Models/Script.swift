//
//  Script.swift
//  mac-prompt
//

import Foundation
import SwiftData

enum LineSpacingStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case compact, comfortable, relaxed
    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .compact: return 4
        case .comfortable: return 12
        case .relaxed: return 22
        }
    }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .comfortable: return "Comfortable"
        case .relaxed: return "Relaxed"
        }
    }
}

@Model
final class Script {
    var id: UUID
    var title: String
    var body: String
    var folder: Folder?
    var tags: [String]
    var isFavorite: Bool
    var isTrashed: Bool
    var createdAt: Date
    var editedAt: Date
    var targetWPM: Int
    var lineSpacingStyleRaw: String
    var editorFontSize: Double
    var accentIndex: Int

    var lineSpacingStyle: LineSpacingStyle {
        get { LineSpacingStyle(rawValue: lineSpacingStyleRaw) ?? .comfortable }
        set { lineSpacingStyleRaw = newValue.rawValue }
    }

    init(
        title: String = "Untitled Script",
        body: String = "",
        folder: Folder? = nil,
        targetWPM: Int = 150,
        editorFontSize: Double = 18,
        accentIndex: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.folder = folder
        self.tags = []
        self.isFavorite = false
        self.isTrashed = false
        self.createdAt = .now
        self.editedAt = .now
        self.targetWPM = targetWPM
        self.lineSpacingStyleRaw = LineSpacingStyle.comfortable.rawValue
        self.editorFontSize = editorFontSize
        self.accentIndex = accentIndex
    }

    /// Word count of `body`, ignoring cue tokens like [PAUSE] and empty whitespace runs.
    var wordCount: Int {
        Script.strippingCueTokens(from: body)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    /// Formatted "M:SS" duration estimate at the given words-per-minute pace.
    func estimatedDuration(at wpm: Int) -> String {
        let safeWPM = max(wpm, 1)
        let totalSeconds = Int((Double(wordCount) / Double(safeWPM)) * 60)
        return Script.formatDuration(totalSeconds: totalSeconds)
    }

    var estimatedDuration: String { estimatedDuration(at: targetWPM) }

    /// A short plain-text preview of the body for library cards, with cue tokens and
    /// markdown emphasis markers stripped so the snippet reads naturally.
    var snippet: String {
        let collapsed = Script.plainDisplayText(from: body)
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if collapsed.count > 140 {
            return String(collapsed.prefix(140)) + "…"
        }
        return collapsed
    }

    static func strippingCueTokens(from text: String) -> String {
        var result = text
        for regex in CueToken.allRegexes {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        return result
    }

    /// `body` with cue tokens removed and `**bold**`/`*italic*` markers unwrapped down
    /// to their inner text — used anywhere the script is shown as plain prose (library
    /// snippets, the Prompter). Only text matched by the same regexes the editor's
    /// syntax highlighter uses is touched, so a stray/unpaired `*` elsewhere in the
    /// script (e.g. "5 * 3 = 15") is left alone instead of being silently deleted.
    static func plainDisplayText(from text: String) -> String {
        var result = strippingCueTokens(from: text)
        for regex in [CueToken.boldRegex, CueToken.italicRegex] {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1"
            )
        }
        return result
    }

    static func formatDuration(totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
