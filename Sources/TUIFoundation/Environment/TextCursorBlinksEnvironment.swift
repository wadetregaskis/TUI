//  🖥️ TUI — A Terminal UI framework for Swift
//  TextCursorBlinksEnvironment.swift
//
//  Whether the text cursor may blink at all: the user's choice in the host's
//  own settings, which no style overrides.
//
//  Created by Wade Tregaskis
//  License: MIT

private struct TextCursorBlinksKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the text cursor may animate: `false` where the user turned its
    /// blinking off in the host's own settings (Windows's text cursor blink
    /// rate set to "None"), read where they are at the machine and written at
    /// the root by the app runner. Then `textCursorStyle`'s animation is
    /// `.none`, whatever a view asked for: an accessibility choice, as
    /// Reduce Motion is, that a style does not take back.
    package var textCursorBlinks: Bool {
        get { self[TextCursorBlinksKey.self] }
        set { self[TextCursorBlinksKey.self] = newValue }
    }
}
