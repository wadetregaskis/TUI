//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalClient+FontQuadrants.swift
//
//  Whether the font each terminal draws in has the quadrants.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TerminalClient {
    /// Whether the font `program` draws in has the quadrants
    /// `▘ ▝ ▖ ▗ ▚ ▞ ▙ ▛ ▜ ▟` (``EnvironmentValues/fontHasQuadrants``): the
    /// console's own answer in the classic Windows console, whose default
    /// font, Consolas, has none (``ConsoleFont``), and `true` for every other
    /// terminal, which draws them as shapes of its own or has a font that does.
    ///
    /// Asked again whenever the console's window changes size, as it does when
    /// its font changes: `WINDOW_BUFFER_SIZE_EVENT`, with the window's cells
    /// unchanged (measured 2026-11-18, the font set with
    /// `SetCurrentConsoleFontEx`).
    static func fontHasQuadrants(_ program: Program) -> Bool {
        switch program {
        case .windowsConsole:
            #if os(Windows)
            return ConsoleFont.hasQuadrants
            #else
            return true
            #endif
        case .appleTerminal, .iTerm2, .ghostty, .warp, .gnomeTerminal, .xtermJS, .windowsTerminal, .tmux,
            .unidentified:
            return true
        }
    }
}
