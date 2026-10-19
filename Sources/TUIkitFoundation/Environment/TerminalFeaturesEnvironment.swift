//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalFeaturesEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TerminalFeatures

/// What the terminal does outside its grid of cells that an app can ask for
/// — which of the features that reach past the window's content show anything
/// here.
///
/// A terminal app draws only cells. Whatever else it changes — the shape of
/// the mouse pointer (``View/pointerStyle(_:)``), a progress bar on the
/// terminal's tab (``View/terminalProgress(_:)``), a desktop notification
/// (``EnvironmentValues/requestAttention``) — it changes by asking the
/// terminal, and only some terminals do as they are asked; none says whether
/// it did, so TUIkit asks only a terminal documented to. Each feature here
/// compiles and runs everywhere, does what it says where its property is
/// `true`, and changes nothing where it is `false`. Read it to offer something
/// else instead:
///
/// ```swift
/// @Environment(\.terminalFeatures) private var terminal
///
/// var body: some View {
///     VStack {
///         if !terminal.showsProgress {
///             ProgressView(value: fraction)
///         }
///         Divider()
///             .pointerStyle(.rowResize)
///         if !terminal.pointerShapes {
///             Text("Drag the line to resize")
///         }
///     }
///     .terminalProgress(.value(fraction))
/// }
/// ```
///
/// It follows from which terminal TUIkit identified at startup and the user's
/// `TUIKIT_*` switches, and is fixed for the run — but for whether the
/// progress bar shows under tmux, which follows the terminals attached to it
/// as they come and go. See `Documentation/Terminals/Terminal compatibility
/// survey.md`, "Pointer shapes (OSC 22)" and "Progress and attention".
public struct TerminalFeatures: Hashable, Sendable {
    /// Whether the terminal sets the mouse pointer's shape when asked, so
    /// ``View/pointerStyle(_:)`` changes the pointer.
    ///
    /// `true` on the terminals documented to (Ghostty from 1.0.0, kitty,
    /// foot, iTerm2 from 3.5.0, xterm), unless turned off; `false` elsewhere,
    /// unless turned on. The app turns it either way with
    /// `TerminalClient.pointerShapeSupport`, and the user with
    /// `TUIKIT_POINTER_SHAPES` (`1` or `0`).
    public let pointerShapes: Bool

    /// Whether TUIkit's own controls set the pointer's shape without being
    /// asked: the I-beam over a text field, a pointing hand over a link or a
    /// button, a resize arrow over a split view's divider or a table's column
    /// edge. Only where a person has seen the terminal put its pointer back as
    /// the app leaves — no terminal yet — or where `TUIKIT_POINTER_SHAPES=all`
    /// asks for them.
    package let controlPointerShapes: Bool

    /// Whether the person sees a view's ``View/terminalProgress(_:)`` as a bar
    /// the terminal draws on its tab, its window or its pane: on Ghostty and
    /// iTerm2; and under tmux, which keeps the bar for its pane, only while
    /// every terminal attached to it is one tmux passes the bar on to — a
    /// client tmux gives its `progressbar` feature, which tmux 3.7c gives
    /// iTerm2 and not Ghostty, Apple Terminal or Warp unless the user sets
    /// `terminal-features`. TUIkit asks tmux, again as clients attach and
    /// detach, so this can change while the app runs.
    ///
    /// A user turns progress on for a terminal TUIkit does not know, or off,
    /// with `TUIKIT_PROGRESS=1` or `0`.
    public let showsProgress: Bool

    /// Whether the terminal posts a desktop notification, so
    /// ``EnvironmentValues/requestAttention`` shows its message: Ghostty and
    /// iTerm2. Where `false` a request rings the terminal's bell, which says
    /// nothing of what it is for.
    ///
    /// A user keeps every request to the bell, or turns notifications on for
    /// a terminal TUIkit does not know, with `TUIKIT_NOTIFICATIONS=0` or `1`.
    public let postsNotifications: Bool

    /// A terminal that does none of these: what a view rendered outside a
    /// running app (a test, a snapshot) reads.
    public static let none = Self()

    /// The features a terminal was found to have; each one left out it does
    /// not have. Built-in control shapes need pointer shapes.
    package init(
        pointerShapes: Bool = false, controlPointerShapes: Bool = false, showsProgress: Bool = false,
        postsNotifications: Bool = false
    ) {
        self.pointerShapes = pointerShapes
        self.controlPointerShapes = pointerShapes && controlPointerShapes
        self.showsProgress = showsProgress
        self.postsNotifications = postsNotifications
    }
}

// MARK: - Environment key

private struct TerminalFeaturesKey: EnvironmentKey {
    /// A view rendered outside a running app has no terminal behind it to ask.
    static let defaultValue = TerminalFeatures.none
}

extension EnvironmentValues {
    /// What the terminal does outside its grid of cells that an app can ask
    /// for — see ``TerminalFeatures``.
    ///
    /// Published by the run loop from the terminal it identified at startup,
    /// and under tmux from the clients attached; read-only, because no view
    /// can change what the terminal does.
    public package(set) var terminalFeatures: TerminalFeatures {
        get { self[TerminalFeaturesKey.self] }
        set { self[TerminalFeaturesKey.self] = newValue }
    }
}
