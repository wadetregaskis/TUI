//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusBreathing.swift
//
//  Whether focus indications animate at all: the user's `TUI_BREATHING=0`, or
//  the app's `Scene.focusBreathing(false)`, hold every one still. A switch of
//  its own, apart from Reduce Motion, which leaves the breath alone (a breath
//  is not spatial motion), and from `.selectionIndicatorStyle(_:)`, which a
//  view below can set back: this one nothing below takes back.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUITerminalHost

private struct FocusBreathesKey: EnvironmentKey {
    // `true`, and not read from the process environment: a key's default must
    // not depend on where a test runs. The render loop writes the user's
    // answer at the root.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether focus indications animate: a focused control's breath, or its
    /// blink under `.selectionIndicatorStyle(.blink)`.
    ///
    /// `true` unless the user set `TUI_BREATHING=0` in the environment the app
    /// runs in (`TerminalClient.focusBreathingRequested`) or the app turned
    /// it off with the TUI-specific `Scene.focusBreathing(_:)`. While it is
    /// `false`, ``selectionIndicatorStyle`` reads
    /// ``TextCursorStyle/Animation/none`` whatever a view set it to, so every
    /// indication sits still at its bright end, and the focus shows by colour
    /// and bold alone.
    ///
    /// Apart from ``accessibilityReduceMotion``, which leaves the breath
    /// alone, and from the text cursor's blink, which ``TextCursorStyle`` sets.
    /// Read-only, so that a view cannot set a breath going for a user who
    /// asked for none. TUI-specific: SwiftUI has no equivalent.
    public package(set) var focusBreathes: Bool {
        get { self[FocusBreathesKey.self] }
        set { self[FocusBreathesKey.self] = newValue }
    }
}

// MARK: - The user's setting

extension TerminalClient {
    /// Whether the user lets focus indications breathe: `false` with
    /// `TUI_BREATHING=0` in the environment the app was started in, and `true`
    /// otherwise. Read once, at first use.
    ///
    /// The app runner hands it to its render loop, which writes it into the
    /// root of every frame's environment, as
    /// ``EnvironmentValues/focusBreathes``, before the scene's own
    /// `.focusBreathing(_:)`. Only the app runner reads it: a headless app's
    /// loop, and every test's, breathes.
    package static let focusBreathingRequested: Bool =
        focusBreathingRequested(environment: ProcessInfo.processInfo.environment)

    /// The rule behind ``focusBreathingRequested``, posed on its input so it
    /// can be asked without changing what a whole process reads.
    static func focusBreathingRequested(environment: [String: String]) -> Bool {
        environment["TUI_BREATHING"] != "0"
    }
}
