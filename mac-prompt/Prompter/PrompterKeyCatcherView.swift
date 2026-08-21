//
//  PrompterKeyCatcherView.swift
//  mac-prompt
//
//  Generalized version of the original ContentView's single-key KeyboardShortcutView:
//  SwiftUI on macOS has no built-in bare-key shortcuts (Space, plain arrows) scoped to
//  a view, so this captures them at the NSView level via first-responder key events.

import AppKit
import SwiftUI

enum PrompterKey: Equatable {
    case space
    case arrowUp
    case arrowDown
    case r
    case m
    case escape
}

struct PrompterKeyCatcherView: NSViewRepresentable {
    var onKeyPress: (PrompterKey) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onKeyPress = onKeyPress
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatcherView)?.onKeyPress = onKeyPress
    }

    final class KeyCatcherView: NSView {
        var onKeyPress: ((PrompterKey) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 49: onKeyPress?(.space)          // Space
            case 126: onKeyPress?(.arrowUp)        // Up arrow
            case 125: onKeyPress?(.arrowDown)      // Down arrow
            case 53: onKeyPress?(.escape)          // Esc
            default:
                if let chars = event.charactersIgnoringModifiers?.lowercased() {
                    if chars == "r" { onKeyPress?(.r) }
                    else if chars == "m" { onKeyPress?(.m) }
                    else { super.keyDown(with: event) }
                } else {
                    super.keyDown(with: event)
                }
            }
        }

        override func viewDidMoveToWindow() {
            window?.makeFirstResponder(self)
        }
    }
}
