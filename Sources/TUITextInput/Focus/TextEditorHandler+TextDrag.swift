//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEditorHandler+TextDrag.swift
//
//  The selected text dragged to somewhere else in the editor, and moved
//  there, as an NSTextView moves it: a press inside the selection and a drag
//  carry it, the caret showing where it will land while the selection stays
//  lit; the release moves it, as one step to undo, and leaves it selected
//  where it landed. A press inside the selection that does not move is a
//  click: the caret goes there and the selection goes. (The owner's Text
//  editing clip, 2026-10-27: "anywhere" dragged to the end of its line.)
//  And text dropped from a drag elsewhere in the app, inserted where it lands
//  (`TextDrop`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIView

extension TextEditorHandler {
    /// Starts carrying the selection, if `position` — where a plain press
    /// landed — is inside it. Returns whether it did.
    func beginTextDrag(at position: TextEditorPosition) -> Bool {
        guard let span = selectionRange, span.start <= position, position < span.end else { return false }
        textDrag = TextDrag(span: span)
        return true
    }

    /// The carried text's drop point follows the pointer: the caret is put at
    /// `position`, the selection set aside (its span still draws lit, from
    /// ``TextDrag/span``).
    func dragText(to position: TextEditorPosition) {
        textDrag?.moved = true
        selectionAnchor = nil
        moveCursor(toLine: position.line, column: position.column)
    }

    /// Ends a drag of the selected text: moves it to where the caret was
    /// carried, or, where the press never moved, makes it the click it was —
    /// the caret at `click`, nothing selected. Returns whether a drag was
    /// under way.
    @MainActor
    func endTextDrag(clickedAt click: TextEditorPosition) -> Bool {
        guard let drag = textDrag else { return false }
        textDrag = nil
        guard drag.moved else {
            clearSelection()
            moveCursor(toLine: click.line, column: click.column)
            return true
        }
        let target = cursor
        selectionAnchor = drag.span.start
        cursor = drag.span.end
        _ = moveSelection(to: target)
        return true
    }

    /// Moves the selected text to `target`, a position in the text as it is,
    /// and selects it there, as one step to undo. Nothing happens where
    /// `target` is inside the selection or on either of its ends: the text
    /// would land where it is. In an editor over an `AttributedString` the
    /// text keeps its own runs where it lands, as an `NSTextView`'s moved text
    /// does, rather than taking the typing attributes there.
    ///
    /// - Returns: Whether the text moved.
    @MainActor
    func moveSelection(to target: TextEditorPosition) -> Bool {
        guard let span = selectionRange else { return false }
        let (start, end) = clamped(span, in: readLines())
        guard target < start || target > end else { return false }
        let moved = selectedText((start, end))
        if attributedSource != nil { holdMovedText((start, end)) }
        defer { attributedSource?.heldInsertion = nil }
        return recordingUndoStep {
            let landing = Self.position(target, afterRemoving: (start, end))
            deleteSelection((start, end))
            moveCursor(toLine: landing.line, column: landing.column)
            let insertedAt = cursor
            insert(moved)
            selectionAnchor = insertedAt
            return true
        }
    }

    /// Inserts text dropped from a drag at `position`, or at the caret for
    /// `nil`, and selects it there, as an `NSTextView` leaves a drop, as one
    /// step to undo. The selection is not replaced: a drop goes where it was
    /// aimed. What the content type turns away is taken out first, as from a
    /// paste, and a drop with nothing left leaves the caret and the selection
    /// as they were. The focus is not moved: an editor takes a drop focused or
    /// not, and leaves the focus where it was (`TextDrop`).
    ///
    /// - Returns: Whether the text changed.
    @MainActor
    func dropText(_ string: String, at position: TextEditorPosition?) -> Bool {
        guard let kept = admitted(string) else { return false }
        let saved = (cursor, selectionAnchor, block)
        let dropped = recordingUndoStep {
            let before = text.wrappedValue
            clearSelection()
            if let position { moveCursor(toLine: position.line, column: position.column) }
            let insertedAt = cursor
            insert(kept)
            guard text.wrappedValue != before else { return false }
            if cursor != insertedAt { selectionAnchor = insertedAt }
            return true
        }
        if dropped {
            publishSelection()
        } else {
            (cursor, selectionAnchor, block) = saved
        }
        return dropped
    }

    /// Where `position`, outside `span`, is once `span` is taken out of the
    /// text: before it, where it was; after it, drawn back by it.
    static func position(_ position: TextEditorPosition, afterRemoving span: SelectionSpan) -> TextEditorPosition {
        guard position > span.end else { return position }
        if position.line == span.end.line {
            return TextEditorPosition(line: span.start.line, column: span.start.column + position.column - span.end.column)
        }
        return TextEditorPosition(line: position.line - (span.end.line - span.start.line), column: position.column)
    }
}

/// A drag of the selected text, under way: the span it was carried from, and
/// whether the pointer has moved since the press.
struct TextDrag {
    let span: SelectionSpan
    var moved = false
}
