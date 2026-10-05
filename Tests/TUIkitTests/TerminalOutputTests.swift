//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalOutputTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// The bytes a `Terminal` sends, read back through a scripted terminal
/// (`ScriptedTerminalOutput`) rather than printed to the console the tests run
/// in.
@MainActor
@Suite("Terminal output")
struct TerminalOutputTests {

    @Test("A write outside a frame goes out at once, and a frame goes out whole at its end")
    func immediateAndFramedWrites() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.write("a")
        #expect(output.writes == ["a"])

        terminal.beginFrame()
        terminal.write("b")
        terminal.moveCursor(toRow: 2, column: 3)
        #expect(output.writes == ["a"], "nothing leaves before the frame ends")
        terminal.endFrame()
        #expect(output.writes == ["a", "b\u{1B}[2;3H"])
    }

    @Test("Raw mode on and off reaches a scripted terminal, which owes no signal anything")
    func rawModeReachesTheScript() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        #expect(terminal.isRawMode)
        #expect(output.bytes.contains("\u{1B}[?2004h"))
        output.clear()
        terminal.disableRawMode()
        #expect(!terminal.isRawMode)
        #expect(output.bytes.contains(Terminal.inputModesOff))
    }
}
