//  🖥️ TUI — A Terminal UI framework for Swift
//  TextKeepsEscapeSequences.swift
//
//  The way back for an app that writes its own escape sequences into the words
//  it draws. Every view strips them by default (the owner's ruling TEXT-ESC,
//  2026-11-10): text from outside the app — a file name, a log line, network
//  data — could otherwise change colours, set the window title or write the
//  clipboard through OSC 52. See
//  `Documentation/Historical/SwiftUI parity process/The owner's decisions of 2026-11-08.md`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

private struct TextKeepsEscapeSequencesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the words drawn below keep the escape sequences and control
    /// characters written into them: set by
    /// ``View/textKeepsEscapeSequences(_:)``, `false` by default.
    ///
    /// Read only where a string holds something the sanitiser would remove
    /// (`String.mayHoldTerminalControls`), so a string without one, which is
    /// virtually every string, costs no lookup: an environment read on every
    /// `Text`'s measure and render was priced at +1.5% to +2.6% when the ASCII
    /// spelling tried it (``RenderContext/textSpelling``).
    package var textKeepsEscapeSequences: Bool {
        get { self[TextKeepsEscapeSequencesKey.self] }
        set { self[TextKeepsEscapeSequencesKey.self] = newValue }
    }
}

extension View {
    /// Lets the words drawn inside this view keep the terminal escape
    /// sequences written into them, for an app that colours its own text.
    ///
    /// Every view draws its words with their escape sequences and control
    /// characters removed (`String.sanitizedForTerminal`), so that text
    /// from outside the app — a file name, a log line, what a server sent —
    /// cannot change colours, set the window's title or write the clipboard.
    /// An app that builds its own colour codes into a string, the output of a
    /// syntax highlighter say, turns that off for the views that show it:
    ///
    /// ```swift
    /// Text(highlighted)  // "\u{1B}[35mlet\u{1B}[0m x = 1"
    ///     .textKeepsEscapeSequences()
    /// ```
    ///
    /// It reaches every word drawn below: a `Text`'s, a label's, a title's, a
    /// table's or list's cells. Then every sequence goes to the terminal as it
    /// was written, whatever it does, so keep it to text the app wrote itself.
    /// A text field shows what is being edited with each control character as
    /// `�` either way, and the status bar, its tooltips and the keyboard
    /// shortcut list, which are drawn outside the app's views, always remove
    /// them.
    ///
    /// TUI-specific: SwiftUI draws no terminal, so a string's escape sequences
    /// mean nothing there.
    ///
    /// - Parameter keeps: Whether the escape sequences are kept. `false`
    ///   removes them, as by default.
    /// - Returns: A view whose words keep, or lose, their escape sequences.
    nonisolated public func textKeepsEscapeSequences(_ keeps: Bool = true) -> some View {
        environment(\.textKeepsEscapeSequences, keeps)
    }
}
