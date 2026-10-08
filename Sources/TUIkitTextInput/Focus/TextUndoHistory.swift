//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoHistory.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// What a text control's undo puts back: the text as it was before each edit,
/// and where the caret was then, newest last.
///
/// Generic over the caret because the text controls place theirs differently:
/// a field's is an index into its one line, an editor's a line and a column.
/// Everything else about undo is the same in both, so it is kept once, here.
///
/// The history describes the text the control itself produced, and only that.
/// The bound text can also be replaced from outside: the app loads another
/// document into the same editor, or clears a field on submit. The records
/// then describe text that is no longer there, and undoing onto the new text
/// would bring back text the control never produced from it. So the control
/// tells the history what it writes (``noteWritten(_:)``), and at every render
/// and before the history is used again (``forgetIfReplaced(current:)``) a
/// text that is not the one last written means a replacement, and the history
/// is forgotten.
///
/// One step per edit, and a key is one edit: typing a word takes as many
/// undos as it has letters. The macOS text system groups a run of typing into
/// one step; this does not. (Inside a running app the app's undo manager
/// groups each event's steps into one undo, as it does on macOS — see
/// ``TextUndoBridge``.)
///
/// It keeps redo as well: an undo puts the state it replaces on the redo
/// stack, a redo puts it back, and a new edit forgets redo.
struct TextUndoHistory<Caret> {
    /// One recorded state, and the mark its step in the app's undo manager is
    /// registered against.
    private struct Entry {
        let text: String
        let caret: Caret
        let mark: TextUndoMark
    }

    /// The recorded states, oldest first.
    private var states: [Entry] = []

    /// The states undo replaced, newest last, each under the mark of the step
    /// that undid it.
    private var redoStates: [Entry] = []

    /// The text the control last wrote, as its binding read it back, or `nil`
    /// before it has written anything.
    private var written: String?

    /// The marks of states let go of since the last ``takeDroppedMarks()``.
    private var dropped: [TextUndoMark] = []

    /// How many states are kept. Recording one more drops the oldest.
    let limit: Int

    init(limit: Int = 50) {
        self.limit = limit
    }

    /// Forgets the history if `current`, the bound text, is not the text the
    /// control last wrote.
    ///
    /// Call it at every render, so a replacement is seen as soon as it is
    /// drawn, and before the control writes anything for the key (or click)
    /// it is handling, for one made since. Comparing strings is cheap when
    /// nothing replaced the text: the binding hands back the storage the
    /// control wrote.
    ///
    /// - Returns: Whether it forgot.
    @discardableResult
    mutating func forgetIfReplaced(current: String) -> Bool {
        guard let written, written != current else { return false }
        forget()
        return true
    }

    /// Forgets every state, undo and redo alike.
    mutating func forget() {
        dropped += heldMarks
        states.removeAll()
        redoStates.removeAll()
        written = nil
    }

    /// Records the state before an edit, and forgets redo: a new edit is a
    /// new branch.
    ///
    /// A state whose text is the newest one's is not recorded again, so an
    /// edit that pushes before a change it then does not make costs no undo
    /// step.
    ///
    /// - Returns: The mark of the state recorded, to register its step
    ///   against; `nil` when nothing was recorded.
    @discardableResult
    mutating func record(text: String, caret: Caret) -> TextUndoMark? {
        if let last = states.last, last.text == text {
            return nil
        }
        dropped += redoStates.map(\.mark)
        redoStates.removeAll()
        let mark = TextUndoMark()
        append(Entry(text: text, caret: caret, mark: mark))
        return mark
    }

    /// Adds a state, dropping the oldest past ``limit``.
    private mutating func append(_ entry: Entry) {
        states.append(entry)
        if states.count > limit {
            dropped.append(states.removeFirst().mark)
        }
    }

    /// Notes the text the control has just written, as its binding reads it
    /// back, so a binding that rewrites what it is given is not taken for a
    /// replacement.
    mutating func noteWritten(_ text: String) {
        written = text
    }

    /// Takes the newest state back for an undo, keeping `current` — the
    /// state it replaces — for redo under the same mark; `nil` when there is
    /// nothing to undo.
    ///
    /// - Parameter mark: The mark of the step doing the undo, or `nil` for
    ///   the control's own undo. Given, only that step's state is taken back,
    ///   so a step that has fallen out of step with the history does nothing
    ///   rather than undo another's state.
    mutating func undo(
        from current: (text: String, caret: Caret), mark: TextUndoMark? = nil
    ) -> (text: String, caret: Caret)? {
        guard let previous = states.last, mark.map({ $0 === previous.mark }) ?? true else { return nil }
        states.removeLast()
        redoStates.append(Entry(text: current.text, caret: current.caret, mark: previous.mark))
        return (previous.text, previous.caret)
    }

    /// Takes the newest undone state back for a redo, keeping `current` for
    /// undo again under the same mark; `nil` when there is nothing to redo.
    /// `mark` as for ``undo(from:mark:)``.
    mutating func redo(
        from current: (text: String, caret: Caret), mark: TextUndoMark? = nil
    ) -> (text: String, caret: Caret)? {
        guard let next = redoStates.last, mark.map({ $0 === next.mark }) ?? true else { return nil }
        redoStates.removeLast()
        append(Entry(text: current.text, caret: current.caret, mark: next.mark))
        return (next.text, next.caret)
    }

    /// The marks of the states let go of since the last call — dropped past
    /// ``limit``, forgotten, or a redo a new edit discarded — whose steps
    /// should leave the app's undo manager too, or it would offer an undo that
    /// does nothing.
    mutating func takeDroppedMarks() -> [TextUndoMark] {
        defer { dropped.removeAll() }
        return dropped
    }

    /// Every mark the history still holds, undo and redo, and those let go of
    /// and not yet taken: what a control going away takes out of the app's
    /// undo manager.
    var allMarks: [TextUndoMark] {
        heldMarks + dropped
    }

    /// The marks of the states held, undo and redo.
    private var heldMarks: [TextUndoMark] {
        states.map(\.mark) + redoStates.map(\.mark)
    }
}
