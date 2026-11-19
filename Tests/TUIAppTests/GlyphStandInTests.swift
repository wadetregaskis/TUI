//  🖥️ TUI — A Terminal UI framework for Swift
//  GlyphStandInTests.swift
//
//  Glyphs a terminal's font lacks, sent as a glyph of the same shape it has:
//  the classic Windows console's, where Consolas has `◄ ► ○` and not
//  `◀ ▶ ◯` (measured 2026-11-18, build 26300).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUITerminalHost

@MainActor
@Suite("Stand-ins for glyphs the terminal's font lacks")
struct GlyphStandInTests {
    /// Consolas's stand-ins, as the console's font is read.
    static let consolas: [Character: Character] = ["\u{25C0}": "\u{25C4}", "\u{25B6}": "\u{25BA}", "\u{25EF}": "\u{25CB}"]

    @Test("A glyph with a stand-in is sent as it, in colour, and its neighbours as they are")
    func standInsAreSent() {
        let writer = FrameDiffWriter(program: .windowsConsole)
        writer.glyphStandIns = Self.consolas
        let row = "\u{1B}[32m\u{25C0}\u{1B}[0m 3 \u{1B}[32m\u{25B6}\u{1B}[0m \u{25EF} Small"
        #expect(
            writer.compensatingCursorAdvance(row)
                == "\u{1B}[32m\u{25C4}\u{1B}[0m 3 \u{1B}[32m\u{25BA}\u{1B}[0m \u{25CB} Small")
    }

    @Test("An escape sequence is left as it is: a link's address is not text")
    func escapesAreKept() {
        let writer = FrameDiffWriter(program: .windowsConsole)
        writer.glyphStandIns = Self.consolas
        let open = "\u{1B}]8;;https://example.com/\u{25B6}\u{1B}\\"
        let close = "\u{1B}]8;;\u{1B}\\"
        #expect(writer.compensatingCursorAdvance("\(open)\u{25B6}\(close)") == "\(open)\u{25BA}\(close)")
    }

    @Test("A glyph with a variation selector is another character, and is left as it is")
    func presentationsAreKept() {
        let writer = FrameDiffWriter(program: .windowsConsole)
        writer.glyphStandIns = Self.consolas
        #expect(writer.compensatingCursorAdvance("\u{25B6}\u{FE0F}") == "\u{25B6}\u{FE0F}")
    }

    @Test("With none, the row is sent as it is")
    func noneLeavesTheRow() {
        let writer = FrameDiffWriter(program: .windowsConsole)
        #expect(writer.compensatingCursorAdvance("\u{25C0} 3 \u{25B6}") == "\u{25C0} 3 \u{25B6}")
    }

    @Test("Each stand-in takes the cells its glyph was laid out in")
    func standInsKeepTheirCells() {
        for (glyph, standIn) in Self.consolas {
            #expect(glyph.terminalWidth == standIn.terminalWidth, "\(glyph) \(standIn)")
            #expect(
                TerminalClient.cursorAdvance(of: glyph, on: .windowsConsole)
                    == TerminalClient.cursorAdvance(of: standIn, on: .windowsConsole),
                "\(glyph) \(standIn)")
        }
    }

    @Test("Only the classic Windows console's font is asked")
    func onlyTheConsoleIsAsked() {
        for program in [TerminalClient.Program.appleTerminal, .iTerm2, .ghostty, .warp, .windowsTerminal, .tmux] {
            #expect(TerminalClient.glyphStandIns(program).isEmpty, "\(program)")
        }
        #if !os(Windows)
        // Off Windows there is no console to ask.
        #expect(TerminalClient.glyphStandIns(.windowsConsole).isEmpty)
        #endif
    }
}
