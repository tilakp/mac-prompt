//
//  CueTextView.swift
//  mac-prompt
//
//  The script editor: an NSTextView that highlights cue tokens and bold/italic
//  markup. SwiftUI's TextEditor cannot style ranges of its text.

import AppKit
import SwiftUI

/// Lets the formatting toolbar insert or wrap text at the cursor, not at the end of
/// the script.
@MainActor
final class CueTextController {
    fileprivate weak var textView: NSTextView?

    func insert(_ string: String) {
        guard let textView else { return }
        textView.insertText(string, replacementRange: textView.selectedRange())
    }

    func wrapSelection(with marker: String) {
        guard let textView else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else {
            insert(marker + "text" + marker)
            return
        }
        let selected = (textView.string as NSString).substring(with: range)
        let wrapped = selected
            .components(separatedBy: "\n")
            .map { Self.wrap($0, with: marker) }
            .joined(separator: "\n")
        textView.insertText(wrapped, replacementRange: range)
    }

    /// Puts `marker` around the text of `line`, inside its leading and trailing spaces.
    /// Markup does not span lines and needs text next to its markers, so each line of
    /// a selection is wrapped on its own.
    nonisolated static func wrap(_ line: String, with marker: String) -> String {
        guard let first = line.firstIndex(where: { !$0.isWhitespace }),
              let last = line.lastIndex(where: { !$0.isWhitespace }) else { return line }
        return String(line[..<first]) + marker + line[first...last] + marker + line[line.index(after: last)...]
    }
}

struct CueTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var controller: CueTextController

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.textStorage?.delegate = context.coordinator
        controller.textView = textView
        context.coordinator.fontSize = fontSize
        context.coordinator.applyHighlighting(to: textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        var needsHighlight = false
        // A change from outside this text view, e.g. the same script edited in a
        // second Library window. Not during IME input: the binding does not have the
        // uncommitted text yet, and replacing it would break the input.
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = text
            // The undo actions refer to ranges in the replaced text.
            coordinator.undoManager.removeAllActions()
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            needsHighlight = true
        }
        if coordinator.fontSize != fontSize {
            coordinator.fontSize = fontSize
            textView.font = .systemFont(ofSize: fontSize)
            needsHighlight = true
        }
        if needsHighlight {
            coordinator.applyHighlighting(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let text: Binding<String>
        var fontSize: Double = 0
        /// This editor's own undo history. By default a text view uses its window's,
        /// which keeps the actions of a script after the editor switches to another.
        let undoManager = UndoManager()
        /// Characters edited since the last highlight. Restyling the whole document on
        /// each keystroke makes the text view lay out all of it again, which is slow
        /// for a long script, so only the paragraphs around this range are restyled.
        private var dirtyRange: NSRange?

        init(text: Binding<String>) {
            self.text = text
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            // Attribute-only edits are our own highlighting.
            guard editedMask.contains(.editedCharacters) else { return }
            // The text view's storage is edited only on the main thread.
            MainActor.assumeIsolated {
                dirtyRange = dirtyRange.map { NSUnionRange($0, editedRange) } ?? editedRange
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Wait while an input method (e.g. Japanese or Chinese) has uncommitted
            // marked text: it is not part of the script yet (do not save it or show it
            // in the Prompter), and restyling it removes its underline and can break
            // the input. Committing it sends this notification again.
            guard !textView.hasMarkedText() else { return }
            text.wrappedValue = textView.string
            guard let dirty = dirtyRange else { return }
            dirtyRange = nil
            applyHighlighting(to: textView, around: dirty)
        }

        func applyHighlighting(to textView: NSTextView) {
            dirtyRange = nil
            applyHighlighting(to: textView, around: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        }

        /// Restyles the paragraphs that `range` touches, plus one paragraph on each side.
        private func applyHighlighting(to textView: NSTextView, around range: NSRange) {
            guard let storage = textView.textStorage else { return }
            let string = storage.string as NSString
            let length = string.length
            // Ranges from earlier edits can end past the text after a later deletion.
            let location = min(range.location, length)
            var target = string.paragraphRange(for: NSRange(location: location, length: min(range.length, length - location)))
            if target.location > 0 {
                target = NSUnionRange(target, string.paragraphRange(for: NSRange(location: target.location - 1, length: 0)))
            }
            if NSMaxRange(target) < length {
                target = NSUnionRange(target, string.paragraphRange(for: NSRange(location: NSMaxRange(target), length: 0)))
            }
            // Not `textView.font`: that is the font of the first character, which is
            // bold when the script starts with a cue or bold text.
            let baseFont = NSFont.systemFont(ofSize: fontSize)

            storage.beginEditing()
            storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: target)

            let plain = storage.string
            for match in ScriptMarkup.cueRegex.matches(in: plain, range: target) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: match.range)
            }
            let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            for match in ScriptMarkup.boldRegex.matches(in: plain, range: target) {
                storage.addAttribute(.font, value: boldFont, range: match.range)
            }
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            for match in ScriptMarkup.italicRegex.matches(in: plain, range: target) {
                storage.addAttribute(.font, value: italicFont, range: match.range)
            }
            storage.endEditing()
        }
    }
}
