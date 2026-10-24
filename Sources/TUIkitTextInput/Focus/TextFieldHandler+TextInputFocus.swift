//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldHandler+TextInputFocus.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

extension TextFieldHandler: TextInputFocusHandler {
    /// A field's Home and End go to the ends of its one line, so Ctrl-A and
    /// Ctrl-E give way here along with the rest. A vertical field's go to the
    /// ends of its text, as the editor's do, and there Ctrl-A and Ctrl-E are
    /// the only keys for the ends of a line, so they keep the key.
    func givesWayToKeyboardShortcut(_ event: KeyEvent) -> Bool {
        editingCommand(for: event)?.givesWayToKeyboardShortcuts(homeAndEndReachLineEnds: !isVertical)
            ?? false
    }

    /// The field's chords: its readline and Option word motions, and the
    /// standard edits it stands in for.
    func editsWith(_ event: KeyEvent) -> Bool {
        TextFieldChord(event) != nil
    }

    /// Its readline chords: ⌃Y, which yanks, is the one of them the undo keys
    /// bind (redo). The chords standing in for ⌘Z and ⇧⌘Z undo and redo, so
    /// they are not kept from them.
    func keepsFromUndoKeys(_ event: KeyEvent) -> Bool {
        editingCommand(for: event) != nil
    }
}
