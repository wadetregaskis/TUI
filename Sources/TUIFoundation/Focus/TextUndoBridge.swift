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
    /// Whether the control's steps hold it, so they outlive its view, as an
    /// `NSTextView`'s steps outlive its place in the window (``TextUndoStep``);
    /// `false`, the default, holds it weakly.
    var stepsKeepControl: Bool { get }
}

extension AppUndoableText {
    package var stepsKeepControl: Bool { false }
}

/// A text control whose steps outlive its view (``AppUndoableText/stepsKeepControl``),
/// while it is off the screen and its steps are in the app's undo manager:
/// asked as each frame ends whether they still mean something
/// (``DepartedUndoSteps/takeOut()``).
@MainActor
package protocol OffScreenUndoKeeping: AnyObject {
    /// Takes the control's steps out of the app's undo manager if the newest
    /// of them would find its text replaced since it last wrote it — as one
    /// on the screen does at its render — and answers whether it still has
    /// steps there to keep.
    func keepsStepsOffScreen() -> Bool
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
/// at the end of the frame that stopped drawing it (``DepartedUndoSteps``) —
/// but a `TextEditor`'s, whose steps keep it (``AppUndoableText/stepsKeepControl``),
/// and stay while its text is the one it left, as SwiftUI's editor's do
/// (measured, `Tools/SwiftUIProbes/TextEditor undo after it leaves (FB4)/`).
/// A replacement is seen where the control renders, which it does in the
/// frame that draws the new text, ahead of the status bar and the next key.
/// The one undo that can find nothing is one in the same burst of input as
/// the replacement, before any frame: the control sees the replacement then,
/// inside the manager's undo, which is spent, and the rest of its steps leave
/// at the frame (taken out from inside the undo, they would leave
/// `NSUndoManager` an emptied step it never drops — measured on macOS 15). A
/// field's step holds it weakly, so it can neither keep one alive nor reach
/// one that is gone; an editor's holds it, so it can restore the text through
/// the binding after the editor has left the screen.
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
        if control.stepsKeepControl { step.kept = control }
        manager.registerUndo(withTarget: mark) { [step, mark] _ in step.run(mark: mark) }
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

    /// Whether the step registered against `mark` is the newest redo in
    /// `manager`: the one its redo would bring back.
    package static func isNewestRedo(_ mark: TextUndoMark, on manager: UndoManager) -> Bool {
        manager.redoActionUserInfoValue(forKey: UndoManager.UserInfoKey(markKey)) as AnyObject? === mark
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
/// A control takes its steps out of the manager when it goes away. One that
/// leaves the screen goes as the frame that stopped drawing it ends, when the
/// state storage lets go of it (`StateStorageDeparting`); that is not where its
/// last reference goes — the focus manager keeps last frame's controls until
/// the next frame begins — and a control no view kept goes wherever that is,
/// in a deinitialiser that promises no isolation. The manager is isolated to
/// the main actor, so neither touches it there: a control leaves its marks
/// here (``add(_:from:)``), and the run loop takes them out (``takeOut()``)
/// as each frame ends, after the state storage has let go of last frame's
/// controls, and as each frame begins, after the focus manager has, before
/// the status bar is sized, so that frame's bar does not offer them.
/// One per app, on its `TUIContext`.
///
/// At the end of the frame, not the next one's start, so the next key's ⌃Z
/// undoes the app's last step: a row's edit field closed by Escape left its
/// typing in the manager until something else drew a frame.
///
/// Not `Sendable`, like the controls that leave their steps here: the compiler
/// keeps them all on the render path, wherever a deinitialiser happens to run.
package final class DepartedUndoSteps {
    /// The marks of each control that has gone away, with the manager its
    /// steps are registered with, which is touched only in ``takeOut()``.
    private var pending: [(marks: [TextUndoMark], manager: UndoManager)] = []

    /// The controls off the screen whose steps stay (``keep(_:)``), held
    /// weakly: their steps hold them, and once the manager lets go of those
    /// steps there is nothing to keep.
    private var offScreen: [WeakOffScreen] = []

    /// A control off the screen, held weakly.
    private struct WeakOffScreen {
        weak var control: (any OffScreenUndoKeeping)?
    }

    /// Notes `control`, which has left the screen with its steps in the app's
    /// undo manager, to be asked as each frame ends whether they still mean
    /// something (``OffScreenUndoKeeping/keepsStepsOffScreen()``).
    package func keep(_ control: any OffScreenUndoKeeping) {
        offScreen.append(WeakOffScreen(control: control))
    }

    /// Leaves `marks`, a control's that is going away, to be taken out of
    /// `manager` at the next end or start of a frame.
    package func add(_ marks: [TextUndoMark], from manager: UndoManager) {
        guard !marks.isEmpty else { return }
        pending.append((marks, manager))
    }

    /// Takes every step left here out of its manager.
    ///
    /// A copy, so that whatever letting go of a step frees can leave steps here
    /// itself.
    ///
    /// - Returns: Whether there were any, so a frame that has already drawn its
    ///   status bar can ask for another that does not offer them.
    ///
    /// And asks each control off the screen whose steps stay whether they
    /// still mean something, letting go of those that answer no.
    @MainActor
    @discardableResult
    package func takeOut() -> Bool {
        var changed = false
        if !offScreen.isEmpty {
            let count = offScreen.count
            offScreen.removeAll { $0.control?.keepsStepsOffScreen() != true }
            changed = offScreen.count != count
        }
        guard !pending.isEmpty else { return changed }
        let taken = pending
        pending = []
        for (marks, manager) in taken {
            TextUndoBridge.removeActions(of: marks, from: manager)
        }
        return true
    }
}

/// One step a text control registered with the undo manager: the control,
/// held weakly so a step can neither keep one alive nor reach one that is
/// gone — and also strongly, for one whose steps keep it
/// (``AppUndoableText/stepsKeepControl``) — the manager its inverse goes back
/// to, and which way it moves.
@MainActor
private final class TextUndoStep {
    weak var control: (any AppUndoableText)?
    /// The control, held, where its steps keep it.
    var kept: (any AppUndoableText)?
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
