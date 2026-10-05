//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+Clipboard.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - Command-Key Stand-Ins

extension TextEditorHandler {
    /// The Command-key stand-in `event` is, among the three the editor binds:
    /// copy, cut and undo. Read before anything else, and in particular before
    /// a selection is dropped, because copy and cut act on it.
    ///
    /// The editor binds only those three of a field's five. Ctrl-V stays the
    /// Emacs page down it has always been here, and a paste reaches the editor
    /// through the terminal's own paste. Ctrl-U, which erases a whole field,
    /// is not bound: one chord erasing a whole document is a different thing.
    func standInCommand(for event: KeyEvent) -> StandInEditingCommand? {
        guard event.ctrl, case .character(let character) = event.key,
            let command = StandInEditingCommand(control: character, shift: event.shift)
        else { return nil }
        switch command {
        case .copy, .cut, .undo, .redo: return command
        case .paste, .erase: return nil
        }
    }

    /// Carries out copy or cut, and returns whether the editor took the key.
    ///
    /// Both act on the selection, and with nothing selected they decline, as a
    /// field's do, so the chord goes on to the app: to its ⌘C or ⌘X, which
    /// arrive as these chords, or to `QuitShortcut.ctrlC`. Undo never gets
    /// here: it is not an edit to record, so the key handling takes it first,
    /// and it always takes the key, since an unclaimed Ctrl-Z reaches layer 4,
    /// which suspends the app.
    func perform(_ command: StandInEditingCommand) -> Bool {
        switch command {
        case .copy, .cut:
            guard let span = selectionRange else { return false }
            clipboard.write(selectedText(span))
            if command == .cut {
                deleteSelection(span)
            }
            return true
        case .undo, .redo, .paste, .erase:
            return false
        }
    }

    /// Ctrl-Z, the stand-in for ⌘Z: undoes the app's newest step where there
    /// is an app — the editor's last edit, unless the app registered something
    /// since — and otherwise puts the text back as it was before the newest
    /// edit, with the cursor where it was, and drops the selection. With
    /// nothing to undo it does nothing, and the key is still the editor's.
    func undo() {
        if let undoManager {
            _ = UndoKey.undo.perform(on: undoManager)
        } else {
            _ = undoOwnStep(mark: nil)
        }
    }

    /// Ctrl-Shift-Z, the stand-in for ⇧⌘Z, where the terminal tells it from
    /// Ctrl-Z: redoes, as ``undo()`` undoes.
    func redo() {
        if let undoManager {
            _ = UndoKey.redo.perform(on: undoManager)
        } else {
            _ = redoOwnStep(mark: nil)
        }
    }

    /// Forgets the history, and the steps registered for it, if the app has
    /// replaced the text since the editor last wrote it.
    func forgetHistoryIfReplaced() {
        undoHistory.forgetIfReplaced(current: text.wrappedValue)
        forgetDroppedSteps()
    }

    /// Takes the steps of the states the history let go of out of the app's
    /// undo manager, so it never offers an undo that does nothing.
    func forgetDroppedSteps() {
        let dropped = undoHistory.takeDroppedMarks()
        if let undoManager { TextUndoBridge.forget(dropped, on: undoManager) }
    }

    /// Restores `state`, as an undo or a redo does.
    private func restore(_ state: (text: String, caret: TextEditorPosition)) {
        write(state.text)
        selectionAnchor = nil
        cursor = state.caret
        clampCursor()
        syncDesiredColumn()
    }
}

// MARK: - AppUndoableText

extension TextEditorHandler: AppUndoableText {
    func undoOwnStep(mark: TextUndoMark?) -> Bool {
        // Runs inside the undo manager's own undo, so a replaced text forgets
        // the history here without touching the manager; the steps it drops
        // leave the manager with the next edit.
        undoHistory.forgetIfReplaced(current: text.wrappedValue)
        guard let previous = undoHistory.undo(from: (text.wrappedValue, cursor), mark: mark) else { return false }
        restore(previous)
        return true
    }

    func redoOwnStep(mark: TextUndoMark?) -> Bool {
        undoHistory.forgetIfReplaced(current: text.wrappedValue)
        guard let next = undoHistory.redo(from: (text.wrappedValue, cursor), mark: mark) else { return false }
        restore(next)
        return true
    }
}

extension TextEditorHandler {

    /// The text `span` covers, its lines joined by line breaks.
    func selectedText(_ span: SelectionSpan) -> String {
        let lines = readLines()
        let (start, end) = clamped(span, in: lines)
        if start.line == end.line {
            let line = lines[start.line]
            return String(line[min(start.column, end.column)..<max(start.column, end.column)])
        }
        var parts = [String(lines[start.line][start.column...])]
        parts += lines[(start.line + 1)..<end.line].map { String($0) }
        parts.append(String(lines[end.line][..<end.column]))
        return parts.joined(separator: "\n")
    }
}
