//  🖥️ TUI — A Terminal UI framework for Swift
//  TextUndoHistory.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

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
/// lane's probes, `Tools/SwiftUIProbes/Undo and the pointer leaving (INPUT)/`;
/// decisions-D1K B-D1K-6): characters typed — a space, a
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
///
/// **Edits, not snapshots** (owner ruling B-PASTE-1-EDITOR, 2026-10-26). A
/// step is kept as the edit it made — where the text changed, the bytes it
/// lost and the bytes it gained (``TextEdit``) — not as the whole text before
/// it: fifty steps over a 16 MiB document held 800 MiB of copies. Only the
/// newest step keeps its text whole, until the step after it is recorded and
/// shows where it ended; then it too becomes an edit. Undo splices the lost
/// bytes back over the gained ones, and redo the other way, so either gives
/// back exactly the bytes there were. A text that does not hold the bytes an
/// edit expects is one the history did not produce, and the history forgets
/// itself rather than splice into it (``undo(from:mark:)``). Texts are
/// compared by their bytes (``TextEdit/sameBytes(_:_:)``), not by `==`, which
/// takes canonically equivalent texts for one. The snapshot
/// history this replaced is the reference `TextUndoHistoryDifferentialTests`
/// checks this one against.
struct TextUndoHistory<Caret: Equatable> {
    /// What a recorded state keeps of its text: the text whole, while it is
    /// the newest step and nothing has shown where it ended; else the edit
    /// from it to the state after it.
    private enum Kept {
        case text(String)
        case edit(TextEdit)
    }

    /// One recorded state, and the mark its step in the app's undo manager is
    /// registered against.
    private struct Entry {
        var kept: Kept
        let caret: Caret
        let mark: TextUndoMark

        /// Whether this state's step, recorded before a change to `text`,
        /// would record the same state again: its text is `text`. Kept as an
        /// edit, that is an edit that changed nothing, since `text` is then
        /// the text it left.
        func leaves(unchanged text: String) -> Bool {
            switch kept {
            case .text(let kept): TextEdit.sameBytes(kept, text)
            case .edit(let edit): edit.removed == edit.inserted
            }
        }
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
        guard let written, !TextEdit.sameBytes(written, current) else { return false }
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
        if continuingTyping, let run = typingRun, run.caret == caret, TextEdit.sameBytes(run.text, text) {
            return nil
        }
        typingRun = nil
        if let last = states.indices.last, states[last].leaves(unchanged: text) {
            // The step is not recorded again, and the newest takes in the edit
            // about to be made, as a snapshot's did: so it keeps its text whole
            // again — it is `text` — until the next step shows where it ends.
            // That edit is still a new branch, so redo goes: a redo after it
            // would bring back a text without it. (The snapshot history kept
            // redo here, and a redo then threw the edit away.)
            states[last].kept = .text(text)
            dropped += redoStates.map(\.mark)
            redoStates.removeAll()
            return nil
        }
        dropped += redoStates.map(\.mark)
        redoStates.removeAll()
        // The newest step ended in `text`, the state before this edit: it can
        // be kept as its edit now.
        if let last = states.indices.last, case .text(let before) = states[last].kept {
            states[last].kept = .edit(TextEdit(from: before, to: text))
        }
        let mark = TextUndoMark()
        append(Entry(kept: .text(text), caret: caret, mark: mark))
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
    @MainActor
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
    ///
    /// The step's edit is taken back off `current`, which is the text the step
    /// left; one that does not hold the bytes the edit put there was not
    /// produced by this history, and it forgets itself and answers `nil`
    /// rather than splice into it.
    mutating func undo(
        from current: (text: String, caret: Caret), mark: TextUndoMark? = nil
    ) -> (text: String, caret: Caret)? {
        guard let previous = states.last, mark.map({ $0 === previous.mark }) ?? true else { return nil }
        let edit: TextEdit
        let before: String
        switch previous.kept {
        case .text(let text):
            edit = TextEdit(from: text, to: current.text)
            before = text
        case .edit(let kept):
            guard let undone = kept.reverted(current.text) else {
                forget()
                return nil
            }
            edit = kept
            before = undone
        }
        typingRun = nil
        states.removeLast()
        redoStates.append(Entry(kept: .edit(edit), caret: current.caret, mark: previous.mark))
        return (before, previous.caret)
    }

    /// Takes the newest undone state back for a redo, keeping `current` for
    /// undo again under the same mark; `nil` when there is nothing to redo.
    /// `mark` as for ``undo(from:mark:)``.
    mutating func redo(
        from current: (text: String, caret: Caret), mark: TextUndoMark? = nil
    ) -> (text: String, caret: Caret)? {
        guard let next = redoStates.last, mark.map({ $0 === next.mark }) ?? true,
            case .edit(let edit) = next.kept
        else { return nil }
        guard let redone = edit.applied(current.text) else {
            forget()
            return nil
        }
        typingRun = nil
        redoStates.removeLast()
        append(Entry(kept: .edit(edit), caret: current.caret, mark: next.mark))
        return (redone, next.caret)
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

    /// The bytes the history holds: whole texts and edits, undo and redo —
    /// for the tests that check it holds edits, not copies.
    var keptBytes: Int {
        (states + redoStates).reduce(0) { sum, entry in
            switch entry.kept {
            case .text(let text): sum + text.utf8.count
            case .edit(let edit): sum + edit.removed.count + edit.inserted.count
            }
        }
    }

    /// The marks of the states held, undo and redo.
    private var heldMarks: [TextUndoMark] {
        states.map(\.mark) + redoStates.map(\.mark)
    }
}

/// One edit to a text, as the bytes it changed: from `offset` (in UTF-8 code
/// units), `removed` gave way to `inserted`. Everything before `offset` and
/// after the removed bytes is untouched, which is what lets the edit be undone
/// and redone on the text alone.
///
/// Byte-exact rather than in characters: splicing bytes back gives back the
/// very bytes there were, whatever grapheme clusters they were part of — a
/// flag split mid-pair, a combining mark on its own, a CRLF one half of which
/// was changed.
struct TextEdit: Equatable {
    /// Where the change starts, in UTF-8 code units from the text's start.
    let offset: Int
    /// The bytes the edit took away.
    let removed: [UInt8]
    /// The bytes it put there.
    let inserted: [UInt8]

    /// The edit that turns `before` into `after`: what lies between their
    /// common start and their common end. A scan of the two, a byte at a time
    /// from each end, and so as long as the text, when the step is recorded —
    /// not on every key.
    ///
    /// The scan reads the two texts' bytes where they lie — a native string's
    /// are contiguous — and copies only the middle that changed.
    init(from before: String, to after: String) {
        var old = before
        var new = after
        let edit =
            old.withUTF8 { oldBytes in
                new.withUTF8 { newBytes in Self.difference(oldBytes, newBytes) }
            }
        (offset, removed, inserted) = edit
    }

    /// Where `old` and `new` differ: the common start's length, and the bytes
    /// of each between the common start and the common end.
    private static func difference(
        _ old: UnsafeBufferPointer<UInt8>, _ new: UnsafeBufferPointer<UInt8>
    ) -> (Int, [UInt8], [UInt8]) {
        let shorter = min(old.count, new.count)
        var start = 0
        while start < shorter, old[start] == new[start] { start += 1 }
        var end = 0
        while end < shorter - start, old[old.count - 1 - end] == new[new.count - 1 - end] { end += 1 }
        return (start, Array(old[start..<(old.count - end)]), Array(new[start..<(new.count - end)]))
    }

    /// Whether `a` and `b` are the same bytes — not `==`, which takes two
    /// canonically equivalent texts for one (a precomposed "é" and an "e"
    /// with a combining accent): a history of byte edits has to see the text
    /// it left, byte for byte. Storage two strings share is answered at once;
    /// otherwise one comparison of the bytes.
    static func sameBytes(_ a: String, _ b: String) -> Bool {
        var a = a
        var b = b
        return a.withUTF8 { x in
            b.withUTF8 { y in
                x.count == y.count
                    && (x.baseAddress == y.baseAddress || x.elementsEqual(y))
            }
        }
    }

    /// `after` with the edit taken back — the text before it — or `nil` where
    /// `after` does not hold the inserted bytes at the edit's place, so is not
    /// the text the edit left.
    func reverted(_ after: String) -> String? {
        Self.splice(after, at: offset, expecting: inserted, putting: removed)
    }

    /// `before` with the edit made again, or `nil` where `before` is not the
    /// text the edit was made to.
    func applied(_ before: String) -> String? {
        Self.splice(before, at: offset, expecting: removed, putting: inserted)
    }

    private static func splice(_ text: String, at offset: Int, expecting: [UInt8], putting: [UInt8]) -> String? {
        let bytes = Array(text.utf8)
        guard offset + expecting.count <= bytes.count, bytes[offset..<(offset + expecting.count)].elementsEqual(expecting)
        else { return nil }
        var result = [UInt8]()
        result.reserveCapacity(bytes.count - expecting.count + putting.count)
        result += bytes[..<offset]
        result += putting
        result += bytes[(offset + expecting.count)...]
        return String(bytes: result, encoding: .utf8)
    }
}
