//
//  CueTextView.swift
//  mac-prompt
//
//  NSTextView-backed editor with regex-based syntax highlighting for cue tokens
//  ([PAUSE], [EMPHASIS], »» FASTER, «« SLOWER) and light markdown emphasis
//  (**bold**, *italic*). SwiftUI's TextEditor can't do inline highlighting, so this
//  wraps AppKit directly, the same approach the original app used for its key catcher.

import AppKit
import SwiftUI

/// Lets the formatting toolbar insert/wrap text at the actual text-view cursor
/// position instead of always appending to the end of the script.
@MainActor
final class CueTextController: ObservableObject {
    fileprivate weak var textView: NSTextView?

    func insert(_ string: String) {
        guard let textView else { return }
        textView.insertText(string, replacementRange: textView.selectedRange())
    }

    func wrapSelection(with marker: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length > 0 {
            let selected = (storage.string as NSString).substring(with: range)
            textView.insertText(marker + selected + marker, replacementRange: range)
        } else {
            insert(marker + "text" + marker)
        }
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
        context.coordinator.applyHighlighting(to: textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        var needsHighlight = false
        if textView.string != text {
            textView.string = text
            needsHighlight = true
        }
        if textView.font?.pointSize != CGFloat(fontSize) {
            textView.font = .systemFont(ofSize: fontSize)
            needsHighlight = true
        }
        if needsHighlight {
            context.coordinator.applyHighlighting(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let text: Binding<String>
        /// Characters edited since the last highlight. Restyling the whole document on
        /// each keystroke makes the text view lay out all of it again, which is slow
        /// for a long script, so only the paragraphs around this range are restyled.
        private var dirtyRange: NSRange?

        init(text: Binding<String>) {
            self.text = text
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

        /// Restyles the paragraphs that `range` touches, plus one paragraph on each side
        /// (a cue such as "»»" + line break + "FASTER" can span a line break).
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
            let baseFont = textView.font ?? .systemFont(ofSize: 18)

            storage.beginEditing()
            storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: target)

            let plain = storage.string
            for match in CueToken.cueRegex.matches(in: plain, range: target) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: baseFont.pointSize), range: match.range)
            }
            let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            for match in CueToken.boldRegex.matches(in: plain, range: target) {
                storage.addAttribute(.font, value: boldFont, range: match.range)
            }
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            for match in CueToken.italicRegex.matches(in: plain, range: target) {
                storage.addAttribute(.font, value: italicFont, range: match.range)
            }
            storage.endEditing()
        }
    }
}
