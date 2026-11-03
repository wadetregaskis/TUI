//  🖥️ TUI — A Terminal UI framework for Swift
//  AccessibilityReduceMotion.swift
//
//  `\.accessibilityReduceMotion`: whether to reduce motion. Where the answer
//  comes from in a terminal — the user's `TUI_REDUCE_MOTION`, the system's
//  setting where the user is provably at this machine, or the app's own
//  `.reduceMotion()` on its scene — is TUI's (`ReduceMotion.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

private struct AccessibilityReduceMotionKey: EnvironmentKey {
    // `false`, and not read from the process environment: a key's default
    // must not depend on where a test runs. The render loop writes the
    // user's answer at the root.
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether to reduce motion — mirrors SwiftUI's `accessibilityReduceMotion`.
    ///
    /// If it is `true`, a view should avoid large animations. TUI's own
    /// transitions follow it: one that has motion (see
    /// ``TransitionProperties/hasMotion``) plays as `.opacity` instead, as
    /// SwiftUI's does.
    ///
    /// TUI also holds still what would move in X and Y: an animated change
    /// of ``View/offset(x:y:)-(Int,Int)``, ``View/position(x:y:)``, padding or a fixed
    /// frame — and an offset in a ``View/visualEffect(_:)`` or a
    /// ``View/shadow(color:radius:x:y:)`` — jumps to its end value (a shadow's
    /// radius still grows), and a dragged view's picture neither lifts out of
    /// its place nor flies back to it when the drag is cancelled: it is at the
    /// pointer from the start, and gone where it is at the end. Motion here means spatial
    /// motion: colour and opacity
    /// animations, the focus breath, the caret's blink, spinners, progress
    /// indicators and symbol effects each say something, and keep moving.
    /// A scroll is held still: a `ScrollView`'s, a `List`'s or a `Table`'s
    /// `scrollTo` or `ScrollPosition` request made inside an animation, and
    /// the page keys under `scrollKeyboardAnimation(_:)`, jump to their target
    /// rather than glide there. An animated `Image` shows its first frame, unless
    /// the app says that picture is content to play regardless, with the TUI-specific
    /// `imageAnimationRespectsReduceMotion(_:)`. An ``Animatable`` view of the app's own, a keyframe animator's
    /// tracks and a custom layout's data animate as they did; read this value
    /// to hold them still too, as in SwiftUI:
    ///
    /// ```swift
    /// @Environment(\.accessibilityReduceMotion) private var reduceMotion
    ///
    /// var body: some View {
    ///     if reduceMotion {
    ///         Image(.file("waving.png"))
    ///     } else {
    ///         Image(.file("waving.gif"))
    ///     }
    /// }
    /// ```
    ///
    /// SwiftUI reads the system's Reduce Motion preference. TUI reads it
    /// only where it is sure the user is at the machine the app runs on — no
    /// ssh session, no remote-session daemon or session keeper among the app's
    /// parents, and inside tmux every attached client passing the same test —
    /// because over ssh the preference would be the server's. It is read at
    /// launch and whenever the terminal regains the focus: macOS's Reduce
    /// motion, or GNOME's animations switched off. `TUI_REDUCE_MOTION` in the
    /// environment the app runs in overrides that either way: `1` is `true`
    /// (``TerminalClient/reduceMotionRequested``) wherever the user is, and `0`
    /// is `false` unless the app asks for less motion itself, with the TUI-specific
    /// `Scene.reduceMotion(_:)`, which also makes it `true`.
    /// Read-only, as SwiftUI's is.
    public package(set) var accessibilityReduceMotion: Bool {
        get { self[AccessibilityReduceMotionKey.self] }
        set { self[AccessibilityReduceMotionKey.self] = newValue }
    }
}
