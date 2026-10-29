//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+TextInputFocus.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TextEditorHandler: TextInputFocusHandler {
    /// The editor's Home and End go to the ends of the document, so Ctrl-A and
    /// Ctrl-E are its only keys for the ends of a line, and they keep the key.
    ///
    /// The find bar's keys, Ctrl-F and Ctrl-G (``yieldsControlFToFind``), give
    /// way as the Emacs Ctrl-F they took over did: they are ⌘F's and ⌘G's
    /// Control chords, and an app's own Find on them wins over the editor's,
    /// as a menu's key equivalent does on macOS. Edit ▸ Find… and Find Next
    /// (`TextEditingCommands`) are no app shortcut: they press these keys.
    func givesWayToKeyboardShortcut(_ event: KeyEvent) -> Bool {
        if isFindChord(event, on: ["f", "F", "g", "G"]) { return true }
        if let command = standInCommand(for: event) { return command.givesWayToKeyboardShortcuts }
        return editingCommand(for: event)?.givesWayToKeyboardShortcuts ?? false
    }

    /// The editor's readline and Option word-motion chords.
    func editsWith(_ event: KeyEvent) -> Bool {
        editingCommand(for: event) != nil
    }

    /// Its readline chords: ⌃Y, which yanks, is the one of them the undo keys
    /// bind (redo). The chords standing in for ⌘Z and ⇧⌘Z undo and redo, so
    /// they are not kept from them.
    func keepsFromUndoKeys(_ event: KeyEvent) -> Bool {
        editingCommand(for: event) != nil
    }
}
