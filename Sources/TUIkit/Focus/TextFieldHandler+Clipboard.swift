//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextFieldHandler+Clipboard.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

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

// MARK: - Clipboard Helpers

/// The clipboard a text field reads and writes.
///
/// In a running app it is the app's ``ClipboardWriter``, which sends each copy
/// where the user will find it — the terminal by OSC 52, or this machine's
/// clipboard when the terminal is on this machine — and says in the status
/// bar when it could not.
///
/// Two closures rather than a direct call, held per handler, so a test can
/// observe what a field *would* have put on the pasteboard without touching
/// the real one. `SecureField` is why: its
/// contract is that nothing is copied at all, and asserting that against the
/// live pasteboard means racing every other test in the process over one
/// shared global — a race that fails in the direction which looks like
/// success, since a test whose sentinel was clobbered skips instead of
/// failing. It also keeps the suite from writing to the developer's
/// pasteboard as a side effect of running.
struct ClipboardAccess: Sendable {
    /// Puts `text` on the clipboard, and answers what became of it; the flag
    /// is ``write(_:announcingSuccess:)``'s.
    var put: @Sendable (_ text: String, _ announcingSuccess: Bool) -> ClipboardWriteResult

    /// Reads the clipboard, or `nil` when there is nothing to read.
    var read: @Sendable () -> String?

    /// The values behind the text this app last copied, where the app keeps
    /// them — see ``TypedClipboard``. Filled in by the clipboard commands from
    /// the environment; `nil` copies and pastes text alone.
    var typed: TypedClipboard?

    /// Puts `text` on the clipboard, and answers what became of it.
    ///
    /// - Parameter announcingSuccess: Whether a plain success earns a line in
    ///   the status bar (see ``ClipboardWriter/write(_:announcingSuccess:)``):
    ///   not for a text control's copy, whose success is what was expected.
    @discardableResult
    func write(_ text: String, announcingSuccess: Bool = false) -> ClipboardWriteResult {
        put(text, announcingSuccess)
    }

    /// The access a running app hands its controls: `writer`'s routes.
    ///
    /// Copies run in event handlers, on the main actor, which is where the
    /// writer's terminal and locality questions are answered.
    init(writer: ClipboardWriter) {
        put = { text, announcing in
            MainActor.assumeIsolated { writer.write(text, announcingSuccess: announcing) }
        }
        read = { MainActor.assumeIsolated { writer.read() } }
        typed = nil
    }

    init(
        put: @escaping @Sendable (_ text: String, _ announcingSuccess: Bool) -> ClipboardWriteResult,
        read: @escaping @Sendable () -> String?, typed: TypedClipboard? = nil
    ) {
        self.put = put
        self.read = read
        self.typed = typed
    }

    /// The clipboard of an environment no context's services reached — a
    /// control a test renders without them: none. A copy reports
    /// ``ClipboardWriteResult/unavailable`` and a paste reads nothing.
    ///
    /// Every render a context drives hands its controls the context's writer
    /// (``EnvironmentValues/applyRuntimeServices(from:)``) — the run loop's,
    /// a headless run's, a snapshot's — and a test that copies hands its
    /// subtree a clipboard of its own. So this is met only where nothing could
    /// be copied to anyway: there is no terminal to send OSC 52 to, and this
    /// machine's clipboard is the app layer's to reach (``ClipboardBackend``),
    /// never a stray render's. Stateless, so it answers from any thread.
    static let unavailable = Self(
        put: { text, _ in text.isEmpty ? .nothingToCopy : .unavailable },
        read: { nil })
}

private struct ClipboardAccessKey: EnvironmentKey {
    static let defaultValue = ClipboardAccess.unavailable
}

extension EnvironmentValues {
    /// The clipboard the copy, cut and paste commands read and write — the
    /// running app's ``ClipboardWriter``, unless a test hands its subtree
    /// another, for the reason ``ClipboardAccess`` gives. A text field or
    /// editor takes the one in its environment when it is created, and keeps
    /// it.
    var clipboardAccess: ClipboardAccess {
        get { self[ClipboardAccessKey.self] }
        set { self[ClipboardAccessKey.self] = newValue }
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
