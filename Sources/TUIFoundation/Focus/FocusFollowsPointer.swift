//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusFollowsPointer.swift
//
//  Whether the focus follows the pointer: the app's `Scene.focusFollowsPointer(_:)`,
//  else the user's `TUI_FOCUS_FOLLOWS_POINTER`, else off.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUITerminalHost

private struct FocusFollowsPointerKey: EnvironmentKey {
    // `nil`: the app said nothing, and the user's variable decides.
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Whether the focus follows the pointer: the user's
    /// ``TerminalClient/focusFollowsPointerRequested``, written at the root of
    /// each frame, replaced by what the app says with the TUI-specific
    /// `Scene.focusFollowsPointer(_:)`, and that by the View menu's choice;
    /// `nil` where none of them said, which is off. The render loop reads it
    /// once the scene's statements are in.
    package var focusFollowsPointer: Bool? {
        get { self[FocusFollowsPointerKey.self] }
        set { self[FocusFollowsPointerKey.self] = newValue }
    }
}

// MARK: - The user's setting

extension TerminalClient {
    /// Whether the user asked for the focus to follow the pointer: `true` with
    /// `TUI_FOCUS_FOLLOWS_POINTER=1` in the environment the app was started
    /// in, `false` with `0`, and `nil` otherwise. Read once, at first use.
    ///
    /// The app runner hands it to its render loop, which uses it where the
    /// scene's own `.focusFollowsPointer(_:)` says nothing. Only the app runner
    /// reads it: in a headless app's loop, and every test's, the focus follows
    /// the pointer only where the scene says so.
    package static let focusFollowsPointerRequested: Bool? =
        focusFollowsPointerRequested(environment: ProcessInfo.processInfo.environment)

    /// The rule behind ``focusFollowsPointerRequested``, posed on its input so
    /// it can be asked without changing what a whole process reads.
    static func focusFollowsPointerRequested(environment: [String: String]) -> Bool? {
        switch environment["TUI_FOCUS_FOLLOWS_POINTER"] {
        case "1": true
        case "0": false
        default: nil
        }
    }
}
