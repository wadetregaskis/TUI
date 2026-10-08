//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+TextInputFocus.swift
//
//  Created by Wade Tregaskis
//  License: MIT

extension TextEditorHandler: TextInputFocusHandler {
    /// The editor's Home and End go to the ends of the document, so Ctrl-A and
    /// Ctrl-E are its only keys for the ends of a line, and they keep the key.
    func givesWayToKeyboardShortcut(_ event: KeyEvent) -> Bool {
        editingCommand(for: event)?.givesWayToKeyboardShortcuts(homeAndEndReachLineEnds: false)
            ?? false
    }
}
