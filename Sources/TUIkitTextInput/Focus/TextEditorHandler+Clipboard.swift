//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditorHandler+Clipboard.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

// MARK: - Command-Key Stand-Ins

extension TextEditorHandler {
    /// The Command-key stand-in `event` is, among the ones the editor binds:
    /// copy, cut, paste, undo and redo. Read before anything else, and in
    /// particular before a selection is dropped, because copy, cut and paste
    /// act on it.
    ///
    /// Ctrl-V pastes here as it does in a field, the stand-in for ⌘V. It was
    /// the Emacs page down, the one Emacs chord an editor kept over a field's
    /// meaning, so the editor was the one text control in which Ctrl-V did
    /// not paste; Page Down still pages, and no other chord was a convention
    /// to move page down to. Ctrl-U, which erases a whole field, is not bound:
    /// one chord erasing a whole document is a different thing.
    func standInCommand(for event: KeyEvent) -> StandInEditingCommand? {
        guard event.ctrl, case .character(let character) = event.key,
            let command = StandInEditingCommand(control: character, shift: event.shift)
        else { return nil }
        switch command {
        case .copy, .cut, .paste, .undo, .redo: return command
        case .erase: return nil
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
            if let block {
                clipboard.write(blockText(block))
                if command == .cut { deleteBlock(block) }
                return true
            }
            guard let span = selectionRange else { return false }
            clipboard.write(selectedText(span))
            if command == .cut {
                deleteSelection(span)
            }
            return true
        case .paste:
            // Over the selection, as a typed key goes; the clipboard's line
            // breaks kept, as the terminal's own paste keeps them. What the
            // content type turns away is dropped first, and a paste with
            // nothing left leaves the selection be.
            guard let pasted = clipboard.read(), !pasted.isEmpty, let kept = admitted(pasted) else { return true }
            if let span = selectionRange { deleteSelection(span) }
            if let block { deleteBlock(block) }
            insert(kept)
            return true
        case .undo, .redo, .erase:
            return false
        }
    }

    /// Ctrl-Z, the stand-in for ⌘Z: undoes the app's newest step where there
    /// is an app — the editor's last edit, unless the app registered something
    /// since — and otherwise puts the text back as it was before the newest
    /// edit, with the cursor where it was, and drops the selection. With
    /// nothing to undo it does nothing, and the key is still the editor's.
    func undo() {
        block = nil
        if let undoManager {
            _ = UndoCommand.undo.perform(on: undoManager)
        } else {
            _ = undoOwnStep(mark: nil)
        }
    }

    /// Ctrl-Shift-Z, the stand-in for ⇧⌘Z, where the terminal tells it from
    /// Ctrl-Z: redoes, as ``undo()`` undoes.
    func redo() {
        block = nil
        if let undoManager {
            _ = UndoCommand.redo.perform(on: undoManager)
        } else {
            _ = redoOwnStep(mark: nil)
        }
    }

    /// Forgets the history, and the steps registered for it, if the app has
    /// replaced the text since the editor last wrote it — and takes out of
    /// the app's undo manager any step its history has already let go of.
    ///
    /// The editor's render calls this every frame, as a field's does (see
    /// `TextFieldHandler.forgetHistoryIfReplaced()`), so a replacement (a
    /// document loaded into the same editor) takes the editor's steps out of
    /// the manager before the next key.
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
        // the history here without touching the manager (see
        // `TextFieldHandler.undoOwnStep`); the steps it drops leave the
        // manager at the next frame.
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

// MARK: - The context menu

extension TextEditorHandler: TextEditingMenuHandler {
    var menuCanCopy: Bool { selectionRange != nil || block?.columns.isEmpty == false }

    var menuCanYank: Bool { !killRing.isEmpty }

    /// Carries out a context-menu command as its key does: an edit is one
    /// step to take back (``recordingUndoStep(_:)``), and the selection is
    /// published after. Yank drops the selection first and inserts at the
    /// caret, as Ctrl-Y does here.
    func performMenuCommand(_ command: TextEditingMenuCommand) {
        defer { publishSelection() }
        defer { forgetMovedRowStartHead() }
        normalizeStaleState()
        forgetHistoryIfReplaced()
        _ = recordingUndoStep {
            switch command {
            case .cut: return perform(StandInEditingCommand.cut)
            case .copy: return perform(StandInEditingCommand.copy)
            case .paste: return perform(StandInEditingCommand.paste)
            case .yank:
                clearSelection()
                yank()
            case .selectAll: selectAll()
            }
            return true
        }
    }
}
