//  🖥️ TUI — A Terminal UI framework for Swift
//  DialogPreferredWidth.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Preferred Dialog Width

/// The width a dialog prefers to lay its body out at before it considers
/// spending more of the screen.
private struct DialogPreferredWidthKey: EnvironmentKey {
    /// Long prose is unpleasant to read as very long lines, and a terminal is
    /// often much wider than a comfortable measure. 100 cells is inside the
    /// ~120 upper bound where reading comfort falls away, while still wide
    /// enough for the tabular content dialogs often carry.
    static let defaultValue = 100
}

extension EnvironmentValues {
    /// The width (in cells) a dialog lays its body out at when it fits, before
    /// it will spend additional horizontal space.
    ///
    /// See ``View/dialogPreferredWidth(_:)``.
    public var dialogPreferredWidth: Int {
        get { self[DialogPreferredWidthKey.self] }
        set { self[DialogPreferredWidthKey.self] = newValue }
    }
}
