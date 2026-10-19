//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalFeaturesEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - TerminalFeatures

/// What the terminal does outside its grid of cells that an app can ask for
/// — which of SwiftUI's features that reach past the window's content work
/// here.
///
/// A terminal app draws only cells. Whatever else it changes — the shape of
/// the mouse pointer, say — it changes by asking the terminal, and only some
/// terminals do as they are asked. Each feature here compiles and runs
/// everywhere, does what it says where its property is `true`, and changes
/// nothing where it is `false`. Read it to offer something else instead:
///
/// ```swift
/// @Environment(\.terminalFeatures) private var terminal
///
/// var body: some View {
///     Divider()
///         .pointerStyle(.columnResize)
///     if !terminal.pointerShapes {
///         Text("Drag the line to resize")
///     }
/// }
/// ```
///
/// Fixed for the run: decided as the app starts, from which terminal it is
/// in and what the user and the app said (see each property).
public struct TerminalFeatures: Hashable, Sendable {
    /// Whether the terminal sets the mouse pointer's shape when asked, so
    /// ``View/pointerStyle(_:)`` changes the pointer.
    ///
    /// `true` on the terminals documented to (Ghostty from 1.0.0, kitty,
    /// foot, iTerm2 from 3.5.0, xterm), unless turned off; `false` elsewhere,
    /// unless turned on. The app turns it either way with
    /// `TerminalClient.pointerShapeSupport`, and the user with
    /// `TUIKIT_POINTER_SHAPES` (`1` or `0`). See *Terminal compatibility
    /// survey*, "Pointer shapes (OSC 22)".
    public let pointerShapes: Bool

    /// Whether TUIkit's own controls set the pointer's shape without being
    /// asked: the I-beam over a text field, a pointing hand over a link or a
    /// button, a resize arrow over a split view's divider or a table's column
    /// edge. Only where a person has seen the terminal put its pointer back as
    /// the app leaves — no terminal yet — or where `TUIKIT_POINTER_SHAPES=all`
    /// asks for them.
    package let controlPointerShapes: Bool

    /// A terminal that does none of these: what a view rendered outside a
    /// running app (a test, a snapshot) reads.
    public static let none = Self(pointerShapes: false, controlPointerShapes: false)

    /// The features a terminal was found to have.
    package init(pointerShapes: Bool, controlPointerShapes: Bool) {
        self.pointerShapes = pointerShapes
        self.controlPointerShapes = pointerShapes && controlPointerShapes
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
    /// Published by the run loop as the app starts; read-only, because no view
    /// can change what the terminal does.
    public package(set) var terminalFeatures: TerminalFeatures {
        get { self[TerminalFeaturesKey.self] }
        set { self[TerminalFeaturesKey.self] = newValue }
    }
}
