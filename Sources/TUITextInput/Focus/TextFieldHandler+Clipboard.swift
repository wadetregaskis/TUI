//  🖥️ TUI — A Terminal UI framework for Swift
//  TextFieldHandler+Clipboard.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Clipboard Operations

extension TextFieldHandler {
    /// Selects all text in the field.
    func selectAll() {
        guard !text.wrappedValue.isEmpty else { return }
        selectionAnchor = 0
        cursorPosition = text.wrappedValue.count
    }

    /// Copies the selected text to the system clipboard.
    ///
    /// Uses `pbcopy` on macOS. Does nothing if no text is selected, and
    /// nothing at all in a ``SecureField`` — see ``TextFieldHandler/isSecure``.
    func copySelection() {
        guard !isSecure, let range = selectionRange else { return }

        let current = text.wrappedValue
        let startIndex = current.index(current.startIndex, offsetBy: range.lowerBound)
        let endIndex = current.index(current.startIndex, offsetBy: range.upperBound)
        let selectedText = String(current[startIndex..<endIndex])

        copyToClipboard(selectedText)
    }

    /// Cuts the selected text to the system clipboard.
    ///
    /// Uses `pbcopy` on macOS. Does nothing if no text is selected, and
    /// nothing at all in a ``SecureField`` — the cut is refused outright
    /// rather than degraded to a delete, because that is what SwiftUI and
    /// `NSSecureTextField` both do, and a Cut that silently became a Delete
    /// would destroy the field's contents while looking like it had copied
    /// them. See ``TextFieldHandler/isSecure``.
    @MainActor
    func cutSelection() {
        guard !isSecure, let range = selectionRange else { return }

        let current = text.wrappedValue
        let startIndex = current.index(current.startIndex, offsetBy: range.lowerBound)
        let endIndex = current.index(current.startIndex, offsetBy: range.upperBound)
        let selectedText = String(current[startIndex..<endIndex])

        copyToClipboard(selectedText)
        pushUndoState()
        deleteRangeWithoutUndo(range)
        clearSelection()
    }

    /// Pastes text from the system clipboard at the cursor position.
    ///
    /// Uses `pbpaste` on macOS. Replaces selection if any.
    @MainActor
    func paste() {
        guard let pastedText = pasteFromClipboard() else { return }
        insertText(pastedText)
    }

    /// Inserts a string at the cursor position in a single operation.
    ///
    /// Used by both clipboard paste (`Ctrl+V`) and bracketed paste
    /// (terminal paste via `Cmd+V`). Replaces selection if any.
    ///
    /// - Parameter string: The text to insert.
    @MainActor
    func insertText(_ string: String) {
        guard !string.isEmpty else { return }
        resetSuggestionNavigation()

        // Every field keeps a pasted line break, one on one line too: SwiftUI's
        // TextField and SecureField bind exactly what was pasted, measured on
        // macOS 15.8.3 (`Tools/SwiftUIProbes/Pasted line breaks and drops
        // (1117)/paste.out`: "ab\ncd" binds "ab\ncd", and no paste submits).
        // Each break is kept as one newline whatever convention the clipboard
        // used (``normalizingLineBreaks(_:)``), where SwiftUI keeps CRLF and
        // CR as they came: a terminal sends a pasted line break as CR, so the
        // clipboard's convention cannot be read back from a paste. U+2028 and
        // U+2029 are categories Zl and Zp, kept as they are. Control characters
        // (category Cc) are stripped on paste so escape sequences and control
        // codes cannot enter the field. A tab is kept, as an AppKit field keeps
        // a pasted one and as TextEditor does: it is text, a column separator
        // copied from a table, and the field draws it as a space
        // (``displayCharacter(_:)``).
        let filteredScalars = string.unicodeScalars.filter { scalar in
            if scalar == "\t" || scalar == "\n" || scalar == "\r" { return true }
            return scalar.properties.generalCategory != .control
        }
        var sanitized = Self.normalizingLineBreaks(String(filteredScalars))

        // Filter by content type if set, and ring the bell once for whatever
        // it turned away, so a paste is never cut short in silence.
        if let contentType = textContentType {
            let filtered = contentType.filterString(sanitized)
            if filtered.count != sanitized.count { bell?.ring() }
            sanitized = filtered
        }
        guard !sanitized.isEmpty else { return }

        pushUndoState()

        // Replace selection if present
        if let range = selectionRange {
            deleteRangeWithoutUndo(range)
            clearSelection()
        }

        // Insert text
        var current = text.wrappedValue
        let index = current.index(current.startIndex, offsetBy: min(cursorPosition, current.count))
        let prefixLength = (current[..<index] + sanitized).count
        current.insert(contentsOf: sanitized, at: index)
        if write(current) { cursorPosition = prefixLength }
    }

    /// What a field on one line draws for `character`: as
    /// ``displayCharacter(_:)`` draws it, and a line break of any kind, U+2028
    /// and U+2029 included, as the replacement character `\u{FFFD}`, one cell.
    ///
    /// The field keeps a pasted line break, as SwiftUI's does
    /// (``insertText(_:)``), but a row cannot show one. AppKit lays the text
    /// after it out on a second line inside the one-line field, which shows
    /// only the first while the field is not being edited (measured on macOS
    /// 15.8.3: `Tools/SwiftUIProbes/Pasted line breaks and drops
    /// (1117)/paste.out`), so text the field holds and would submit goes
    /// unseen. Drawn as a mark instead, every character stays in view, and the
    /// break draws as an app's own `"\n"` always has. Not a space, which would
    /// read as one typed; and never the raw U+2028 or U+2029, a line break the
    /// terminal is handed to draw in a cell, which no survey of TUI's has
    /// measured a terminal doing.
    nonisolated static func singleLineDisplayCharacter(_ character: Character) -> Character {
        character.isNewline ? "\u{FFFD}" : displayCharacter(character)
    }
}

// MARK: - Dropped Text

extension TextFieldHandler {
    /// Inserts dropped text at `offset`, or at the caret for `nil`, and
    /// selects it there, as an `NSTextView` leaves a drop. The selection is
    /// not replaced: a drop goes where it was aimed, between characters.
    ///
    /// Through ``insertText(_:)``, as a paste goes, so the text is filtered,
    /// its line breaks kept or not, and its content type applied as a paste's
    /// are, the binding written as for typed text, and the drop is one step to
    /// undo. A drop the field turns away entirely leaves the caret and the
    /// selection as they were.
    ///
    /// - Returns: Whether the text changed.
    @MainActor
    func dropText(_ string: String, atOffset offset: Int?) -> Bool {
        let before = text.wrappedValue
        let (caret, anchor) = (cursorPosition, selectionAnchor)
        if let offset { cursorPosition = max(0, min(offset, before.count)) }
        clearSelection()
        let start = cursorPosition
        insertText(string)
        guard text.wrappedValue != before else {
            (cursorPosition, selectionAnchor) = (caret, anchor)
            return false
        }
        if cursorPosition > start { selectionAnchor = start }
        publishSelection()
        return true
    }
}

extension TextFieldHandler {
    /// Copies text to the clipboard.
    fileprivate func copyToClipboard(_ text: String) {
        clipboard.write(text)
    }

    /// Pastes text from the clipboard, or `nil` when unavailable.
    fileprivate func pasteFromClipboard() -> String? {
        clipboard.read()
    }
}

// MARK: - The context menu

extension TextFieldHandler: TextEditingMenuHandler {
    var menuCanCopy: Bool { !isSecure && hasSelection }

    var menuCanYank: Bool { !killRing.isEmpty }

    /// Carries out a context-menu command as its key does: each edit records
    /// its own step to take back, and the selection is published after.
    func performMenuCommand(_ command: TextEditingMenuCommand) {
        defer { publishSelection() }
        defer { forgetMovedRowStartHead() }
        normalizeStaleState()
        switch command {
        case .cut: cutSelection()
        case .copy: copySelection()
        case .paste: paste()
        case .yank: _ = perform(TextEditingCommand.yank)
        case .selectAll: selectAll()
        }
    }
}
