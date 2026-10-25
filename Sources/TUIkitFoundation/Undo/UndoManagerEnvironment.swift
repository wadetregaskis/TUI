//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoManagerEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore

// MARK: - The environment value

private struct UndoManagerKey: EnvironmentKey {
    /// No undo outside a running app — a snapshot render, a test — as
    /// SwiftUI's is `nil` "when the environment represents a context that
    /// doesn't support undo and redo operations".
    ///
    /// Computed, not stored: the macOS 26 SDK isolates `UndoManager` to the
    /// main actor, which makes it `Sendable`, and the macOS 15 SDK does not,
    /// where a stored static of the type is a global Swift 6 rejects. Nothing
    /// is stored, so there is nothing to make safe, under either.
    static var defaultValue: UndoManager? { nil }
}

/// An `UndoManager` carried into `MainActor.assumeIsolated` from code that is
/// not isolated, though it only ever runs on the main actor.
///
/// The macOS 26 SDK isolates `UndoManager` to the main actor, which makes it
/// `Sendable` and this needless; the macOS 15 SDK — the Command Line Tools'
/// — does not, and there sending the manager into the closure is a data-race
/// error. A box rather than `nonisolated(unsafe)`, which the 26 SDK would
/// warn is unnecessary. Use it only where the manager is touched inside the
/// closure, on the main actor.
package struct MainActorUndoManager: @unchecked Sendable {
    package let manager: UndoManager

    package init(_ manager: UndoManager) {
        self.manager = manager
    }
}

extension EnvironmentValues {
    /// The undo manager used to register a view's undo operations.
    ///
    /// One per app, made by the run loop, and `nil` outside a running app.
    /// Register an operation's inverse with it, and the user undoes and redoes
    /// it from the keyboard or the status bar:
    ///
    /// ```swift
    /// @Environment(\.undoManager) private var undoManager
    ///
    /// func delete(_ item: Item) {
    ///     store.remove(item)
    ///     undoManager?.registerUndo(withTarget: store) { $0.insert(item) }
    ///     undoManager?.setActionName("Delete")
    /// }
    /// ```
    ///
    /// For a value a view owns — a `@State` array a list's `onMove` reorders —
    /// TUIkit's `UndoManager.registerRestoring(_:to:actionName:)` registers
    /// the undo and its redo from a binding, with no class to call back.
    /// A list's moves and deletions, and a drop, register nothing by
    /// themselves, as in SwiftUI: the app knows the data.
    ///
    /// ``TextField`` and ``TextEditor`` register their own edits with it, so
    /// undo means something in an app that registers nothing itself; a
    /// control's leave it when the control leaves the screen. A
    /// ``SecureField``'s do not.
    ///
    /// ## Undoing in a terminal
    ///
    /// A terminal app has no Edit menu and no ⌘Z. The keys
    /// (``UndoCommand/defaultShortcuts``), which an app's own keyboard
    /// shortcut on the same chord takes first:
    ///
    /// - **Undo:** Ctrl-Z, Ctrl-minus and Ctrl-/, on every terminal. Most
    ///   terminals send the same byte for Ctrl-minus, Ctrl-_ and Ctrl-/, and
    ///   the same for Ctrl-Z and Ctrl-Shift-Z, so in a legacy encoding all of
    ///   those undo. A focused text control's Ctrl-Z, the stand-in for ⌘Z, is
    ///   this undo too, and its Ctrl-Shift-Z this redo.
    /// - **Redo:** Ctrl-Shift-Z and Ctrl-_ (Ctrl-Shift-minus) where the
    ///   terminal tells them from Ctrl-Z and Ctrl-minus — the kitty keyboard
    ///   protocol, ``TerminalCapabilities/Feature/shiftedKeys``; and Option-_
    ///   where the terminal sends Option as Meta (or reports Option under the
    ///   protocol). Ctrl-Y is the text controls' yank, and is not taken.
    /// - **Ctrl-Z is the shell's suspend key too.** Bound to undo, with
    ///   nothing to undo it does nothing; an app whose users expect it to
    ///   stop the app takes it out of undo with ``Scene/undoShortcuts(_:)``,
    ///   which sets either list app-wide, and it suspends again.
    /// - **The status bar** shows "undo" while there is something to undo and
    ///   "redo" while there is something to redo, each naming the first of its
    ///   keys the terminal can deliver, and a click performs it, so every
    ///   terminal has a route to both.
    ///
    /// Each event's registrations are one undo step, as `UndoManager` groups
    /// them on macOS. Where Foundation has no `UndoManager` (Linux), TUIkit
    /// provides one with the same Swift surface. See
    /// `Documentation/Terminals/Terminal compatibility survey.md`, "Undo and redo".
    public package(set) var undoManager: UndoManager? {
        get { self[UndoManagerKey.self] }
        set { self[UndoManagerKey.self] = newValue }
    }

    /// Where a text control leaves its steps in ``undoManager`` when it goes
    /// away, for the next frame to take out: published with the manager, and
    /// `nil` where there is none.
    package var departedUndoSteps: DepartedUndoSteps? {
        get { self[DepartedUndoStepsKey.self] }
        set { self[DepartedUndoStepsKey.self] = newValue }
    }
}

private struct DepartedUndoStepsKey: EnvironmentKey {
    static let defaultValue: DepartedUndoSteps? = nil
}
