//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextUndoBridge.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

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
/// (``forget(_:on:)``), and so does every state of a control that goes away,
/// at the start of the next frame (``DepartedUndoSteps``).
/// A replacement is seen where the control renders, which it does in the
/// frame that draws the new text, ahead of the status bar and the next key.
/// The one undo that can find nothing is one in the same burst of input as
/// the replacement, before any frame: the control sees the replacement then,
/// inside the manager's undo, which is spent, and the rest of its steps leave
/// at the frame (taken out from inside the undo, they would leave
/// `NSUndoManager` an emptied step it never drops — measured on macOS 15). A
/// step holds its control weakly, so it can neither keep one alive nor reach
/// one that is gone.
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

    /// Takes the steps registered against `marks` out of `manager`, at once.
    ///
    /// Every caller is on the main actor — a render, a key, a click — which
    /// is asked of the isolation, not of the thread. On Linux the main actor
    /// is drained by a pool thread after the first suspension (see
    /// `StackGuard`), so `Thread.isMainThread`, which this asked until the
    /// 2026-10-05 review, sent every removal there to a `Task` that ran after
    /// the frame: the status bar went on offering the steps. A control going
    /// away does not come here: its deinitialiser promises no isolation at
    /// all, and leaves its steps to ``DepartedUndoSteps``.
    static func forget(_ marks: [TextUndoMark], on manager: UndoManager) {
        guard !marks.isEmpty else { return }
        MainActor.assumeIsolated { removeActions(of: marks, from: manager) }
    }

    @MainActor
    fileprivate static func removeActions(of marks: [TextUndoMark], from manager: UndoManager) {
        for mark in marks { manager.removeAllActions(withTarget: mark) }
    }
}

/// The undo steps of text controls that have gone away, waiting to be taken
/// out of the app's undo manager.
///
/// A control takes its steps out of the manager when it goes away, and it goes
/// away wherever its last reference is let go of. That is the main actor in
/// practice — the start of the frame after the one that stopped drawing it,
/// when the focus manager lets go of the last frame's controls — but a
/// deinitialiser promises no isolation, and the manager is isolated to the
/// main actor. So the control does not touch the manager there: it leaves its
/// marks here (``add(_:from:)``), and every frame takes them out
/// (``takeOut()``) as it begins, after last frame's controls are let go of and
/// before the status bar is sized, so that frame's bar does not offer them. A
/// control let go of later in a frame has its steps taken out at the next.
/// One per app, on its `TUIContext`.
///
/// Locked, because a deinitialiser can run on any thread; an empty list costs
/// a frame one lock and a check.
final class DepartedUndoSteps: @unchecked Sendable {
    private let lock = NSLock()

    /// The marks of each control that has gone away, with the manager its
    /// steps are registered with. Under ``lock``.
    private var pending: [(marks: [TextUndoMark], manager: UndoManager)] = []

    /// Leaves `marks`, a control's that is going away, to be taken out of
    /// `manager` at the start of the next frame. Callable from anywhere.
    func add(_ marks: [TextUndoMark], from manager: UndoManager) {
        guard !marks.isEmpty else { return }
        lock.lock()
        pending.append((marks, manager))
        lock.unlock()
    }

    /// Takes every step left here out of its manager.
    ///
    /// Outside the lock, so that whatever letting go of a step frees can
    /// leave steps here itself.
    @MainActor
    func takeOut() {
        var taken: [(marks: [TextUndoMark], manager: UndoManager)] = []
        lock.lock()
        swap(&taken, &pending)
        lock.unlock()
        for (marks, manager) in taken { TextUndoBridge.removeActions(of: marks, from: manager) }
    }
}
