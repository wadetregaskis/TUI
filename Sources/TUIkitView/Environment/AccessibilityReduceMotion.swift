//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AccessibilityReduceMotion.swift
//
//  `\.accessibilityReduceMotion`: whether to reduce motion. Where the answer
//  comes from in a terminal — the user's `TUIKIT_REDUCE_MOTION`, the system's
//  setting where the user is provably at this machine, or the app's own
//  `.reduceMotion()` on its scene — is TUIkit's (`ReduceMotion.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

private struct AccessibilityReduceMotionKey: EnvironmentKey {
    // `false`, and not read from the process environment: a key's default
    // must not depend on where a test runs. The render loop writes the
    // user's answer at the root.
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether to reduce motion — mirrors SwiftUI's `accessibilityReduceMotion`.
    ///
    /// If it is `true`, a view should avoid large animations. TUIkit's own
    /// transitions follow it: one that has motion (see
    /// ``TransitionProperties/hasMotion``) plays as `.opacity` instead, as
    /// SwiftUI's does.
    ///
    /// TUIkit also holds still what would move in X and Y: an animated change
    /// of ``View/offset(x:y:)``, ``View/position(x:y:)``, padding or a fixed
    /// frame — and an offset in a ``View/visualEffect(_:)`` or a
    /// ``View/shadow(color:radius:x:y:)`` — jumps to its end value (a shadow's
    /// radius still grows), and a dragged view's picture neither lifts out of
    /// its place nor flies back to it when the drag is cancelled: it is at the
    /// pointer from the start, and gone where it is at the end. Motion here means spatial
    /// motion: colour and opacity
    /// animations, the focus breath, the caret's blink, spinners, progress
    /// indicators and symbol effects each say something, and keep moving.
    /// Scrolling is never animated in a terminal, so it moves at once either
    /// way. An ``Animatable`` view of the app's own, a keyframe animator's
    /// tracks and a custom layout's data animate as they did; read this value
    /// to hold them still too, as in SwiftUI.
    ///
    /// SwiftUI reads the system's Reduce Motion preference. TUIkit reads it
    /// only where it is sure the user is at the machine the app runs on — no
    /// ssh session, no remote-session daemon or session keeper among the app's
    /// parents, and inside tmux every attached client passing the same test —
    /// because over ssh the preference would be the server's. It is read at
    /// launch and whenever the terminal regains the focus: macOS's Reduce
    /// motion, or GNOME's animations switched off. It is also `true` when the
    /// user set `TUIKIT_REDUCE_MOTION=1` in the environment the app runs in
    /// (``TerminalClient/reduceMotionRequested``), wherever that is, or the
    /// app asked for it with the TUI-specific `Scene.reduceMotion(_:)`.
    /// Read-only, as SwiftUI's is.
    public package(set) var accessibilityReduceMotion: Bool {
        get { self[AccessibilityReduceMotionKey.self] }
        set { self[AccessibilityReduceMotionKey.self] = newValue }
    }
}
