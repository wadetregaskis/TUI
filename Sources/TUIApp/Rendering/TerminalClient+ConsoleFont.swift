//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalClient+ConsoleFont.swift
//
//  What the font each terminal draws in lacks: the quadrants, and glyphs that
//  have a stand-in of the same shape.
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

    /// The glyphs the font `program` draws in lacks, each with one of the same
    /// shape and cells it has, which the writer sends in its place
    /// (`FrameDiffWriter.glyphStandIns`): in the classic Windows console,
    /// `◀ ▶ ◯` as `◄ ► ○` where its font is Consolas (``ConsoleFont/standIns``),
    /// and none for every other terminal, whose font is not asked. Asked again
    /// on each resize, as ``fontHasQuadrants(_:)`` is.
    static func glyphStandIns(_ program: Program) -> [Character: Character] {
        switch program {
        case .windowsConsole:
            #if os(Windows)
            return ConsoleFont.standIns
            #else
            return [:]
            #endif
        case .appleTerminal, .iTerm2, .ghostty, .warp, .gnomeTerminal, .xtermJS, .windowsTerminal, .tmux,
            .unidentified:
            return [:]
        }
    }
}
