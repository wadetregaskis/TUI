//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalInput.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Terminal Input

/// A single input event read from the terminal.
///
/// Terminals report keys, mouse activity, focus changes and (under the kitty
/// keyboard protocol) modifier keys through the same input stream,
/// distinguished only by the escape sequence that wraps each event. `TerminalInput` is the discriminated union the parser
/// returns so call sites can pattern-match against each kind.
public enum TerminalInput: Sendable, Equatable {
    /// A keyboard event (key press, paste, etc.).
    case key(KeyEvent)

    /// A mouse event (click, release, motion, drag, scroll).
    case mouse(MouseEvent)

    /// The terminal window, tab or pane gained (`isFocused == true`) or lost
    /// (`false`) focus: a focus report, `ESC [ I` or `ESC [ O`.
    ///
    /// A terminal sends these only while focus reporting (DEC private mode
    /// 1004) is on, and many never send them at all: a terminal without the
    /// mode, or tmux without its `focus-events` option. Treat one as a hint
    /// that arrived, never as a signal that is guaranteed to.
    case focusChanged(isFocused: Bool)

    /// A modifier key went down or came up on its own, or a lock key changed
    /// state, leaving the modifiers as reported.
    ///
    /// Only a terminal speaking the kitty keyboard protocol sends one; see
    /// ``ModifierKeyState``. Never a key: a Shift held for a Shift-click is not
    /// typing, so nothing that hears keys hears these.
    case modifierKeys(ModifierKeyState)
}

extension TerminalInput {
    /// The key event this input is, or `nil` for any other kind.
    package var keyEvent: KeyEvent? {
        if case .key(let event) = self { return event }
        return nil
    }
}
