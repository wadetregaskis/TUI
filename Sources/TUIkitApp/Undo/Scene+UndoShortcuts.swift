//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+UndoShortcuts.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitCore
import TUIkitFoundation

// MARK: - Environment and the scene modifier

private struct UndoShortcutsKey: EnvironmentKey {
    static let defaultValue = UndoShortcuts.default
}

extension EnvironmentValues {
    /// The app's undo and redo keys, as a scene set them — see
    /// ``Scene/undoShortcuts(_:)``. Read by the run loop from the root
    /// environment; the keys are app-wide, so a view setting it changes
    /// nothing.
    var undoShortcuts: UndoShortcuts {
        get { self[UndoShortcutsKey.self] }
        set { self[UndoShortcutsKey.self] = newValue }
    }
}

extension Scene {
    /// Rebinds the keys that undo and redo, app-wide.
    ///
    /// TUI-specific: SwiftUI's undo is the Edit menu's ⌘Z, which no terminal
    /// sends, so the keys are TUIkit's own (``UndoCommand/defaultShortcuts``).
    /// A command not mentioned keeps its defaults; a value replaces them
    /// (`[chord]`, ``ShortcutSet/only(_:)``), adds to them
    /// (`.default.and(…)`) or removes them all (``ShortcutSet/unbound``).
    ///
    /// The case it is for: Ctrl-Z, bound to undo by default, is also the
    /// shell's suspend key. An app whose users expect Ctrl-Z to stop it takes
    /// Ctrl-Z out of undo, and Ctrl-Z suspends again, exactly as it did:
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .undoShortcuts([.undo: .only(.init("-", modifiers: .control), .init("/", modifiers: .control))])
    /// ```
    ///
    /// The status bar's "undo" and "redo" name the first key of each that the
    /// terminal can deliver; a focused text control's own Ctrl-Z and
    /// Ctrl-Shift-Z, the stand-ins for ⌘Z and ⇧⌘Z, are the control's and
    /// unaffected. See ``UndoShortcuts``.
    ///
    /// - Parameter overrides: The app's changes, by command.
    /// - Returns: A scene whose undo and redo keys are these.
    public func undoShortcuts(_ overrides: [UndoCommand: ShortcutSet]) -> some Scene {
        _EnvironmentScene(content: self) { $0.undoShortcuts = UndoShortcuts(overrides) }
    }
}
