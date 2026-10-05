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
    /// The recorded states, oldest first.
    private var states: [(text: String, caret: Caret)] = []

    /// The states undo replaced, newest last.
    private var redoStates: [(text: String, caret: Caret)] = []

    /// The text the control last wrote, as its binding read it back, or `nil`
    /// before it has written anything.
    private var written: String?

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
    /// - Returns: Whether it forgot, so a control can forget the steps it
    ///   registered with the app's undo manager too.
    @discardableResult
    mutating func forgetIfReplaced(current: String) -> Bool {
        guard let written, written != current else { return false }
        forget()
        return true
    }

    /// Forgets every state, undo and redo alike.
    mutating func forget() {
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
    /// - Returns: Whether it recorded a step.
    @discardableResult
    mutating func record(text: String, caret: Caret) -> Bool {
        if let last = states.last, last.text == text {
            return false
        }
        redoStates.removeAll()
        append(text: text, caret: caret)
        return true
    }

    private mutating func append(text: String, caret: Caret) {
        states.append((text, caret))
        if states.count > limit {
            states.removeFirst()
        }
    }

    /// Notes the text the control has just written, as its binding reads it
    /// back, so a binding that rewrites what it is given is not taken for a
    /// replacement.
    mutating func noteWritten(_ text: String) {
        written = text
    }

    /// Takes the newest state, or `nil` when there is nothing to undo.
    mutating func popLast() -> (text: String, caret: Caret)? {
        states.popLast()
    }

    /// Takes the newest state back for an undo, keeping `current` — the
    /// state it replaces — for redo; `nil` when there is nothing to undo.
    mutating func undo(from current: (text: String, caret: Caret)) -> (text: String, caret: Caret)? {
        guard let previous = states.popLast() else { return nil }
        redoStates.append(current)
        return previous
    }

    /// Takes the newest undone state back for a redo, keeping `current` for
    /// undo again; `nil` when there is nothing to redo.
    mutating func redo(from current: (text: String, caret: Caret)) -> (text: String, caret: Caret)? {
        guard let next = redoStates.popLast() else { return nil }
        append(text: current.text, caret: current.caret)
        return next
    }
}

// MARK: - The app's undo manager

/// A text control that can take one step of its own history back or forward
/// — the half of undo the app's undo manager calls into.
protocol AppUndoableText: AnyObject {
    /// Takes one step of the control's history back; `false` with nothing to
    /// undo.
    func undoOwnStep() -> Bool
    /// Takes one undone step forward again; `false` with nothing to redo.
    func redoOwnStep() -> Bool
}

/// How a text control's own history and the app's undo manager stay one
/// history.
///
/// The control keeps the STATES (``TextUndoHistory``): it alone knows its text
/// and caret, and it must undo per edit even with no app behind it, in a test
/// or a snapshot. The app's undo manager keeps a STEP for each, registered
/// against the control: undoing the step takes the control's newest state
/// back and registers the redo, and redoing it does the reverse. So an undo
/// from anywhere — Ctrl-minus, the status bar, the app's own code, the
/// control's Ctrl-Z — undoes the newest step in the app, whether that is the
/// control's typing or something the app registered after it, as ⌘Z does in a
/// window on macOS. Each event's steps are one undo there (`groupsByEvent`),
/// and each of them takes one state back, so the two never drift apart.
///
/// The undo manager is isolated to the main actor and the controls are not,
/// though they only ever run there.
enum TextUndoBridge {
    /// Registers the step the control just recorded: undone, it takes the
    /// control one state back and registers its redo.
    static func registerEdit(of control: some AppUndoableText, on manager: UndoManager) {
        // The control is only ever touched on the main actor, where this runs;
        // the compiler cannot know that of a type that is not isolated.
        nonisolated(unsafe) let control = control
        MainActor.assumeIsolated { register(control, on: manager, undoing: true) }
    }

    @MainActor
    private static func register<Control: AppUndoableText>(
        _ control: Control, on manager: UndoManager, undoing: Bool
    ) {
        // Without grouping by event a registration needs a group around it,
        // or Foundation's `UndoManager` raises; with it, the event's group
        // is opened for it. Inside an undo or a redo the manager's own group
        // is open.
        let needsGroup = !manager.groupsByEvent && manager.groupingLevel == 0
        if needsGroup { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: control) { control in
            let moved = undoing ? control.undoOwnStep() : control.redoOwnStep()
            if moved { register(control, on: manager, undoing: !undoing) }
        }
        if needsGroup { manager.endUndoGrouping() }
    }

    /// Forgets every step the control registered: its history has gone (the
    /// app replaced its text), or, for a field, its editing has ended.
    static func forgetEdits(of control: some AppUndoableText, on manager: UndoManager) {
        nonisolated(unsafe) let control = control
        MainActor.assumeIsolated { manager.removeAllActions(withTarget: control) }
    }
}
