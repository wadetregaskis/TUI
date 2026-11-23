//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFieldHandler+FocusLifecycle.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Focus Lifecycle

extension TextFieldHandler {
    func onFocusReceived() {
        // Ensure cursor is at a valid position
        clampCursorPosition()
        onEditingChanged?(true)
    }

    func onFocusLost() {
        // The pop-up never outlives the focus session, and a fresh session
        // starts with the keyboard at the caret and the menu closed.
        suggestionsOpen = false
        resetSuggestionNavigation()
        // Editing has ended: the commit point for values that apply live —
        // a combo box records its recents here, not just on Enter.
        if let onEditingChanged { committing { onEditingChanged(false) } }
    }

    /// Runs `commit`, and puts the caret at the end of the text where it
    /// rewrote it: a value field's commit of "1234" shows "1,234", and a
    /// caret left at the fourth character put the next digit between the 3
    /// and the 4. A commit that leaves the text as it was leaves the caret.
    func committing(_ commit: () -> Void) {
        let before = text.wrappedValue
        commit()
        let after = text.wrappedValue
        guard after != before else { return }
        selectionText = after
        cursorPosition = after.count
        clearSelection()
    }
}
