//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoHistory.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation

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
/// One step per edit, except a run of typing, which is one step, as the
/// macOS text system makes it (measured on macOS 15.8, `NSTextView`, the INPUT
/// lane's probe; decisions-D1K B-D1K-6): characters typed — a space, a
/// newline and a tab among them, Option-Return's and Option-Tab's too — and
/// Backspace, each at the caret the edit before it left, with no selection;
/// Ctrl-O's newline joins the run, but the caret it leaves behind ends it. A caret moved elsewhere ends the run
/// (one moved away and back does not), as does any other edit: Delete, a
/// word's deletion, a paste, a cut, an undo. A pause does not. Typing or
/// Backspace over a selection starts a new run. So typing a word, a
/// mistake rubbed out, and the rest of the sentence is one undo
/// (``record(text:caret:continuingTyping:)``, ``noteTyped(text:caret:)``).
/// Inside a running app the app's undo manager groups each event's steps into
/// one undo too, as it does on macOS — see ``TextUndoBridge``; a key that
/// continues a run registers nothing there, and a step registered there by
/// anything else since the run's own ends the run, as it does on macOS
/// (``endTypingRun(unlessNewestIn:)``), so the undos come back in the order
/// of the edits. The focus moving away and back with nothing registered
/// meanwhile does not end it.
///
/// It keeps redo as well: an undo puts the state it replaces on the redo
/// stack, a redo puts it back, and a new edit forgets redo.
struct TextUndoHistory<Caret: Equatable> {
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

    /// The text and caret the last edit of a run of typing left, while that
    /// run may go on: a typing edit made from exactly this state is part of
    /// the same step (``record(text:caret:continuingTyping:)``). With them,
    /// the mark of that step, which the app's undo manager is asked about
    /// (``endTypingRun(unlessNewestIn:)``).
    private var typingRun: (text: String, caret: Caret, mark: TextUndoMark?)?

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
        typingRun = nil
    }

    /// Records the state before an edit, and forgets redo: a new edit is a
    /// new branch.
    ///
    /// A state whose text is the newest one's is not recorded again, so an
    /// edit that pushes before a change it then does not make costs no undo
    /// step.
    ///
    /// An edit that continues a run of typing — `continuingTyping`, made
    /// from the state the run's last edit left — is part of that run's step,
    /// and records nothing. Any other ends the run; a typing edit then starts
    /// one, once it has noted the state it leaves (``noteTyped(text:caret:)``).
    ///
    /// - Parameter continuingTyping: Whether the edit is typing — a character,
    ///   or Backspace — with no selection, so it may continue a run.
    /// - Returns: The mark of the state recorded, to register its step
    ///   against; `nil` when nothing was recorded.
    @discardableResult
    mutating func record(text: String, caret: Caret, continuingTyping: Bool = false) -> TextUndoMark? {
        if continuingTyping, let run = typingRun, run.caret == caret, run.text == text {
            return nil
        }
        typingRun = nil
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

    /// Notes the state a typing edit — a character, or Backspace — has just
    /// left, so a typing edit made from it next continues the same step.
    mutating func noteTyped(text: String, caret: Caret) {
        typingRun = (text, caret, states.last?.mark)
    }

    /// Ends the run of typing unless its step is still the newest in the
    /// app's undo manager, `manager`: a step registered there since — another
    /// control's typing, an action of the app's — leaves the run's below it,
    /// and the next key continuing the run would be undone after that step,
    /// though typed after it. Measured on macOS 15.8: `NSTextView` makes the
    /// typing after such a step a step of its own
    /// (`TextUndoBridge.isNewestStep(_:on:)`). Nothing to ask with no
    /// manager.
    mutating func endTypingRun(unlessNewestIn manager: UndoManager?) {
        guard let manager, let mark = typingRun?.mark, !TextUndoBridge.isNewestStep(mark, on: manager) else { return }
        typingRun = nil
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
        typingRun = nil
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
        typingRun = nil
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
