//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldHandler+Clipboard.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitFoundation

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
    func insertText(_ string: String) {
        guard !string.isEmpty else { return }
        resetSuggestionNavigation()

        // A field on one line strips the line breaks from pasted text; a
        // vertical one keeps them, each as one newline whatever convention
        // the clipboard used.
        var sanitized =
            isVertical
            ? Self.normalizingLineBreaks(string)
            : string.replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")

        // Filter by content type if set.
        if let contentType = textContentType {
            sanitized = contentType.filterString(sanitized)
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
        current.insert(contentsOf: sanitized, at: index)
        write(current)
        cursorPosition += sanitized.count
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
