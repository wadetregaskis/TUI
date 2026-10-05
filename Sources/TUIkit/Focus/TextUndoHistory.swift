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
/// tells the history what it writes (``noteWritten(_:)``), and before the
/// history is used again (``forgetIfReplaced(current:)``) a text that is not
/// the one last written means a replacement, and the history is forgotten.
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

    /// Forgets the history if `current`, the bound text before the control
    /// records or undoes an edit, is not the text the control last wrote.
    ///
    /// Call it before the control writes anything for the key (or click) it
    /// is handling. Comparing strings is cheap when nothing replaced the text:
    /// the binding hands back the storage the control wrote.
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

/// What one of a text control's undo steps is registered against in the app's
/// undo manager: one per state its ``TextUndoHistory`` keeps, carried from
/// undo to redo and back.
///
/// Not the control. `NSUndoManager` keeps its target unowned, so a step
/// registered against a control that has left the screen and been freed would
/// call into freed memory; a mark lives as long as the step that holds it.
/// And one per state, not per control, so the step of the one state the
/// history drops past its limit can leave the manager on its own
/// (`removeAllActions(withTarget:)`), which a manager offers no other way to
/// do.
final class TextUndoMark: Sendable {}

// MARK: - The app's undo manager

/// A text control that can take one step of its own history back or forward
/// — the half of undo the app's undo manager calls into.
protocol AppUndoableText: AnyObject {
    /// Takes the step `mark` back, if it is the newest of the control's
    /// history (any newest step for `nil`); `false` when it did nothing.
    func undoOwnStep(mark: TextUndoMark?) -> Bool
    /// Takes the undone step `mark` forward again, as ``undoOwnStep(mark:)``.
    func redoOwnStep(mark: TextUndoMark?) -> Bool
}

/// How a text control's own history and the app's undo manager stay one
/// history.
///
/// The control keeps the STATES (``TextUndoHistory``): it alone knows its text
/// and caret, and it must undo per edit even with no app behind it, in a test
/// or a snapshot. The app's undo manager keeps a STEP for each, registered
/// against the state's ``TextUndoMark``: undoing the step takes the control's
/// state back and registers the redo, and redoing it does the reverse. So an
/// undo from anywhere — Ctrl-minus, the status bar, the app's own code, the
/// control's Ctrl-Z — undoes the newest step in the app, whether that is the
/// control's typing or something the app registered after it, as ⌘Z does in a
/// window on macOS. Each event's steps are one undo there (`groupsByEvent`),
/// and each of them takes one state back, so the two never drift apart.
///
/// The manager never offers a step that does nothing. A state the history
/// lets go of — past its limit, forgotten when the app replaced the text, a
/// redo a new edit discarded — takes its step out with it
/// (``forget(_:on:)``), and so does every state of a control that goes away.
/// A step holds its control weakly, so it can neither keep one alive nor
/// reach one that is gone.
///
/// The undo manager is isolated to the main actor and the controls are not,
/// though they only ever run there.
enum TextUndoBridge {
    /// Registers the step the control just recorded, against `mark`: undone,
    /// it takes the control one state back and registers its redo.
    static func registerEdit(of control: some AppUndoableText, mark: TextUndoMark, on manager: UndoManager) {
        // The control is only ever touched on the main actor, where this runs;
        // the compiler cannot know that of a type that is not isolated.
        nonisolated(unsafe) let control = control
        MainActor.assumeIsolated { register(control, mark: mark, on: manager, undoing: true) }
    }

    @MainActor
    private static func register<Control: AppUndoableText>(
        _ control: Control, mark: TextUndoMark, on manager: UndoManager, undoing: Bool
    ) {
        // Without grouping by event a registration needs a group around it,
        // or Foundation's `UndoManager` raises; with it, the event's group
        // is opened for it. Inside an undo or a redo the manager's own group
        // is open.
        let needsGroup = !manager.groupsByEvent && manager.groupingLevel == 0
        if needsGroup { manager.beginUndoGrouping() }
        // The mark is captured as well as passed: the manager keeps its target
        // unowned, and the step is what keeps the mark alive.
        manager.registerUndo(withTarget: mark) { [weak control, mark] _ in
            guard let control else { return }
            let moved = undoing ? control.undoOwnStep(mark: mark) : control.redoOwnStep(mark: mark)
            if moved { register(control, mark: mark, on: manager, undoing: !undoing) }
        }
        if needsGroup { manager.endUndoGrouping() }
    }

    /// Takes the steps registered against `marks` out of `manager`.
    ///
    /// On the main actor at once; from anywhere else — a control's last
    /// reference let go off the main thread — on the main actor next, the
    /// marks kept alive until then by this call.
    static func forget(_ marks: [TextUndoMark], on manager: UndoManager) {
        guard !marks.isEmpty else { return }
        #if canImport(WASILibc)
            // wasip1 has one thread, the main actor's, and its Foundation no
            // `Thread` to ask.
            MainActor.assumeIsolated { removeActions(of: marks, from: manager) }
        #else
            if Thread.isMainThread {
                MainActor.assumeIsolated { removeActions(of: marks, from: manager) }
            } else {
                Task { @MainActor in removeActions(of: marks, from: manager) }
            }
        #endif
    }

    @MainActor
    private static func removeActions(of marks: [TextUndoMark], from manager: UndoManager) {
        for mark in marks { manager.removeAllActions(withTarget: mark) }
    }
}
