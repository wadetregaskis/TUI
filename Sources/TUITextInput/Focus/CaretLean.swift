//  🖥️ TUI — A Terminal UI framework for Swift
//  CaretLean.swift
//
//  Which row a caret leans to where a row wrapped, as each key leaves it:
//  the vertical field's and the editor's one rule (decisions D4X-FULLER).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

/// Where a row soft-wrapped, one offset is both the end of that row and the
/// start of the next. The macOS text system keeps, per caret, which of the two
/// it is drawn at, and each motion sets it (measured on macOS 15.8,
/// `Tools/SwiftUIProbes/Vertical TextField keys, caret and size (wave 6b)/affinity-motions.out`):
///
/// - **upstream**, at the end of the earlier row: typing, Backspace, Forward
///   Delete, a paste — any edit — and Ctrl-E, the end of a line (⌘→ too);
///   and a selection set from outside the text view;
/// - **downstream**, at the start of the later row: the arrow keys, Up and
///   Down included, word moves, and Ctrl-A, the start of a line (⌘← too);
///   and a click, which puts the caret on the row clicked.
enum CaretLean {
    /// The lean a key leaves the caret with: upstream after an edit or the
    /// end of a line, downstream after any other key that moved it, and
    /// `current` after a key that did neither.
    static func after(
        _ event: KeyEvent, edited: Bool, moved: Bool, current: TextSelectionAffinity
    ) -> TextSelectionAffinity {
        if edited { return .upstream }
        guard moved else { return current }
        if event.ctrl, case .character(let letter) = event.key,
            TextEditingCommand(control: letter, alt: event.alt) == .moveToEndOfLine
        {
            return .upstream
        }
        return .downstream
    }
}
