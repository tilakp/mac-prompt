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
            // Command/Control/Option combinations are not prompter keys (⌘R must not record).
            guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                  let key = prompterKey(for: event) else {
                super.keyDown(with: event)
                return
            }
            // Holding a key down sends repeats. Only the speed keys act on them, or
            // holding Space or R would toggle playback or recording on and off.
            if event.isARepeat, key != .arrowUp, key != .arrowDown { return }
            onKeyPress?(key)
        }

        private func prompterKey(for event: NSEvent) -> PrompterKey? {
            switch event.keyCode {
            case 49: return .space          // Space
            case 126: return .arrowUp       // Up arrow
            case 125: return .arrowDown     // Down arrow
            case 53: return .escape         // Esc
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "r": return .r
                case "m": return .m
                default: return nil
                }
            }
        }

        override func viewDidMoveToWindow() {
            window?.makeFirstResponder(self)
            // Do not reopen the Prompter at the next launch: a restored Prompter window
            // turns the camera and mic on and starts scrolling before the user asks.
            // (`.restorationBehavior(.disabled)` needs macOS 15; this target is 14.6.)
            window?.isRestorable = false
        }
    }
}
