//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalFocusReport.swift
//
//  What a focus report from the terminal (mode 1004) does to the scene's
//  phase: the one rule the run loop and a test's `TestApp` both follow.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TUIContext {
    /// Moves the scene between ``ScenePhase/active`` and
    /// ``ScenePhase/inactive`` for a focus report: in when `isFocused`, out
    /// otherwise.
    ///
    /// While the scene is ``ScenePhase/background`` it does nothing: that phase
    /// belongs to the suspend (or a hand-off), which sets `.active` again
    /// itself. A report of the phase the scene already has changes nothing: a
    /// terminal may report focus in as reporting is enabled.
    ///
    /// - Returns: Whether the phase moved, and so whether the screen needs a
    ///   frame to show it.
    package func movePhase(forTerminalFocus isFocused: Bool) -> Bool {
        guard scenePhase != .background else { return false }
        let phase: ScenePhase = isFocused ? .active : .inactive
        guard scenePhase != phase else { return false }
        scenePhase = phase
        return true
    }
}
