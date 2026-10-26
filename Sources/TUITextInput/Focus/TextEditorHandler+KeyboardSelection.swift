//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+KeyboardSelection.swift
//
//  Selecting from the keyboard in a text editor, as a text field selects and
//  as NSTextView does: Shift with a motion key, and a plain arrow landing at
//  the selection's edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension TextEditorHandler {
    /// Handles a key that selects, or that ends a selection by moving to its
    /// edge; `false` for every other key, which the editor then handles.
    ///
    /// - Shift with a motion key extends the selection from where it began:
    ///   Shift-←/→ a character, Shift-Option-←/→ a word, Shift-↑/↓ a line,
    ///   Shift-Page Up/Down a page, Shift-Home/End to the document's ends. The
    ///   first such key anchors the selection at the caret, as a Shift-click
    ///   does (``startOrExtendSelection(from:)``); the caret then moves as the
    ///   key would move it, and the selection is anchor…caret. Back to the
    ///   anchor, it is empty again.
    /// - A plain ← or → with a selection puts the caret at its start or its end
    ///   and drops it, rather than moving a character from the caret.
    ///
    /// A text field had all of this; the editor selected only with the mouse,
    /// and Shift-arrows just moved the caret (the owner, 2026-10-25: TextEditor
    /// should support everything TextField does).
    func handleSelectionKey(_ event: KeyEvent) -> Bool {
        guard !event.ctrl else { return false }
        if event.shift, let motion = selectingMotion(for: event) {
            block = nil
            startOrExtendSelection()
            motion()
            // Back on the anchor there is nothing selected.
            if selectionAnchor == cursor { selectionAnchor = nil }
            return true
        }
        guard !event.shift, !event.alt, let span = selectionRange else { return false }
        switch event.key {
        case .left: cursor = span.start
        case .right: cursor = span.end
        default: return false
        }
        clearSelection()
        syncDesiredColumn()
        return true
    }

    /// The caret motion a Shift-modified key selects over, or `nil` for a key
    /// that does not move it.
    private func selectingMotion(for event: KeyEvent) -> (() -> Void)? {
        switch event.key {
        case .left: event.alt ? moveWordLeft : moveLeft
        case .right: event.alt ? moveWordRight : moveRight
        case .up: { self.moveVertical(by: -1) }
        case .down: { self.moveVertical(by: 1) }
        case .pageUp: { self.movePage(by: -1) }
        case .pageDown: { self.movePage(by: 1) }
        case .home: moveToStartOfDocument
        case .end: moveToEndOfDocument
        default: nil
        }
    }
}
