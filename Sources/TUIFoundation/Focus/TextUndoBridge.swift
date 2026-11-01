//  🖥️ TUI — A Terminal UI framework for Swift
//  TextUndoBridge.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Synchronization

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
package final class TextUndoMark: Sendable {
    /// No arguments, spelled out because the implicit initializer is internal
    /// and TUITextInput's undo histories make these.
    package init() {}
}

// MARK: - The app's undo manager

/// A text control that can take one step of its own history back or forward
/// — the half of undo the app's undo manager calls into.
@MainActor
package protocol AppUndoableText: AnyObject {
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
/// The undo manager, the controls and everything here are isolated to the main
/// actor.
@MainActor
package enum TextUndoBridge {
    /// Registers the step the control just recorded, against `mark`: undone,
    /// it takes the control one state back and registers its redo.
    package static func registerEdit(of control: some AppUndoableText, mark: TextUndoMark, on manager: UndoManager) {
        register(control, mark: mark, on: manager, undoing: true)
    }

    fileprivate static func register(
        _ control: any AppUndoableText, mark: TextUndoMark, on manager: UndoManager, undoing: Bool
    ) {
        // Without grouping by event a registration needs a group around it,
        // or Foundation's `UndoManager` raises; with it, the event's group
        // is opened for it. Inside an undo or a redo the manager's own group
        // is open.
        let needsGroup = !manager.groupsByEvent && manager.groupingLevel == 0
        if needsGroup { manager.beginUndoGrouping() }
        // The mark is captured as well as passed: the manager keeps its target
        // unowned, and the step is what keeps the mark alive.
        let step = TextUndoStep(control: control, manager: manager, undoing: undoing)
        manager.registerUndo(withTarget: mark) { [step, mark] _ in
            // The manager runs its steps on the main actor. The macOS 26 SDK's
            // handler says so; the macOS 15 SDK's (the Command Line Tools')
            // does not, and is `@Sendable` besides — hence the step, isolated,
            // rather than the control and the manager captured here.
            MainActor.assumeIsolated { step.run(mark: mark) }
        }
        label(manager, with: mark)
        if needsGroup { manager.endUndoGrouping() }
    }

    /// Puts `mark` in the user info of the step being built, so a control can
    /// ask whether its step is still the newest (``isNewestStep(_:on:)``).
    /// Only inside the step's group: `NSUndoManager` raises with none open,
    /// and with registration disabled the registration opened none.
    package static func label(_ manager: UndoManager, with mark: TextUndoMark) {
        guard manager.groupingLevel > 0 else { return }
        manager.setActionUserInfoValue(mark, forKey: UndoManager.UserInfoKey(markKey))
    }

    /// The user-info key a text control's step carries its mark under.
    private static let markKey = "TUI.TextUndoMark"

    /// Whether the step registered against `mark` is the newest in `manager`:
    /// the one its undo would take back.
    ///
    /// What ends a run of typing as the macOS text system ends one (measured
    /// on macOS 15.8 with `NSTextView`s sharing a window's undo manager, the
    /// INPUT lane's probes, `Tools/SwiftUIProbes/Undo and the pointer leaving (INPUT)/`):
    /// typing that follows a step registered by anything else — another text
    /// control's typing, an action of the app's — is a step of its own, so the
    /// undos come back in the order of the edits.
    /// The focus moving away and back with nothing registered meanwhile does
    /// not end the run.
    package static func isNewestStep(_ mark: TextUndoMark, on manager: UndoManager) -> Bool {
        manager.undoActionUserInfoValue(forKey: UndoManager.UserInfoKey(markKey)) as AnyObject? === mark
    }

    /// Takes the steps registered against `marks` out of `manager`, at once.
    ///
    /// A control going away does not come here: its deinitialiser promises no
    /// isolation at all, and leaves its steps to ``DepartedUndoSteps``.
    package static func forget(_ marks: [TextUndoMark], on manager: UndoManager) {
        guard !marks.isEmpty else { return }
        removeActions(of: marks, from: manager)
    }

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
/// Not `Sendable`, like the controls that leave their steps here: the compiler
/// keeps them all on the render path, wherever a deinitialiser happens to run.
package final class DepartedUndoSteps {
    /// The marks of each control that has gone away, with the manager its
    /// steps are registered with, which is touched only in ``takeOut()``.
    private var pending: [(marks: [TextUndoMark], manager: UndoManager)] = []

    /// Leaves `marks`, a control's that is going away, to be taken out of
    /// `manager` at the start of the next frame.
    package func add(_ marks: [TextUndoMark], from manager: UndoManager) {
        guard !marks.isEmpty else { return }
        pending.append((marks, manager))
    }

    /// Takes every step left here out of its manager.
    ///
    /// A copy, so that whatever letting go of a step frees can leave steps here
    /// itself.
    @MainActor
    package func takeOut() {
        guard !pending.isEmpty else { return }
        let taken = pending
        pending = []
        for (marks, manager) in taken {
            TextUndoBridge.removeActions(of: marks, from: manager)
        }
    }
}

/// One step a text control registered with the undo manager: the control,
/// held weakly so a step can neither keep one alive nor reach one that is
/// gone, the manager its inverse goes back to, and which way it moves.
@MainActor
private final class TextUndoStep {
    weak var control: (any AppUndoableText)?
    let manager: UndoManager
    let undoing: Bool

    init(control: any AppUndoableText, manager: UndoManager, undoing: Bool) {
        self.control = control
        self.manager = manager
        self.undoing = undoing
    }

    /// Takes the control one state back (or forward), and registers the
    /// opposite step.
    func run(mark: TextUndoMark) {
        guard let control else { return }
        let moved = undoing ? control.undoOwnStep(mark: mark) : control.redoOwnStep(mark: mark)
        if moved { TextUndoBridge.register(control, mark: mark, on: manager, undoing: !undoing) }
    }
}
