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
    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            applyHighlighting(to: textView)
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            let baseFont = textView.font ?? .systemFont(ofSize: 18)

            storage.beginEditing()
            storage.setAttributes([.font: baseFont, .foregroundColor: NSColor.labelColor], range: fullRange)

            let plain = storage.string
            for match in CueToken.cueRegex.matches(in: plain, range: fullRange) {
                storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range)
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: baseFont.pointSize), range: match.range)
            }
            let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            for match in CueToken.boldRegex.matches(in: plain, range: fullRange) {
                storage.addAttribute(.font, value: boldFont, range: match.range)
            }
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            for match in CueToken.italicRegex.matches(in: plain, range: fullRange) {
                storage.addAttribute(.font, value: italicFont, range: match.range)
            }
            storage.endEditing()
        }
    }
}
