//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextEditor+Wrapping.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The modifier

extension View {
    /// Whether a ``TextEditor`` in this view wraps its long lines — a TUIkit
    /// setting with no SwiftUI counterpart.
    ///
    /// By default an editor wraps, as SwiftUI's does: a line wider than the
    /// editor continues on the rows below, breaking after a run of spaces,
    /// which hangs at the end of the row it breaks, or between the characters
    /// of a word too long for a row — the macOS text system's rules (see
    /// ``TextEditor``). `false` keeps each line on one row and scrolls the
    /// editor sideways to follow the caret, as many terminal editors do: the
    /// shape for code, logs and tables in plain text, whose columns a wrap
    /// would break.
    ///
    /// ```swift
    /// TextEditor(text: $source)
    ///     .textEditorWrapsLines(false)
    /// ```
    ///
    /// - Parameter wraps: Whether long lines wrap.
    /// - Returns: A view whose editors wrap, or scroll sideways.
    public func textEditorWrapsLines(_ wraps: Bool = true) -> some View {
        environment(\.textEditorWrapsLines, wraps)
    }
}

// MARK: - Environment

private struct TextEditorWrapsLinesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether a ``TextEditor`` wraps its long lines — see
    /// ``View/textEditorWrapsLines(_:)``.
    var textEditorWrapsLines: Bool {
        get { self[TextEditorWrapsLinesKey.self] }
        set { self[TextEditorWrapsLinesKey.self] = newValue }
    }
}
