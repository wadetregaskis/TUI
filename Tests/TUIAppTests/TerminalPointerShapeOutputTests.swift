//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalPointerShapeOutputTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

/// The OSC 22 bytes a `Terminal` sends for the pointer's shape, read back
/// through a scripted terminal: written on a change only, again after a mouse
/// mode change, put back at the teardown before the mouse modes go off, owed
/// to a signal, and never sent to a host that is not documented to take it.
@MainActor
@Suite("Terminal pointer shape output")
struct TerminalPointerShapeOutputTests {
    private static let ghostty = ["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.3.1"]

    private static func osc22(_ name: String) -> String { "\u{1B}]22;\(name)\u{1B}\\" }

    @Test("A shape is written when it changes and not again; none is Ghostty's `default`")
    func writtenOnChange() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        output.clear()
        terminal.showPointerShape(nil)
        #expect(output.bytes.isEmpty, "nothing was set, so nothing is put back")
        terminal.showPointerShape(.link)
        #expect(output.bytes == Self.osc22("pointer"))
        output.clear()
        terminal.showPointerShape(.link)
        #expect(output.bytes.isEmpty)
        terminal.showPointerShape(nil)
        #expect(output.bytes == Self.osc22("default"))
    }

    @Test("A mouse mode change, which on Ghostty resets the pointer, has the shape written again")
    func rewrittenAfterAModeChange() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        terminal.applyMouseSupport(.standard)
        terminal.showPointerShape(.columnResize)
        output.clear()
        terminal.applyMouseSupport(.full)
        terminal.showPointerShape(.columnResize)
        #expect(output.bytes.hasSuffix(Self.osc22("ew-resize")))
        output.clear()
        terminal.applyMouseSupport(.full)
        terminal.showPointerShape(.columnResize)
        #expect(output.bytes.isEmpty, "no mode change, nothing to write")
    }

    @Test("The teardown puts the pointer back before the mouse modes go off, and a signal is owed the same")
    func resetAtTheTeardown() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        terminal.applyMouseSupport(.full)
        terminal.showPointerShape(.link)
        #expect(terminal.signalDebt.contains(PointerShapeHost.reset + Terminal.inputModesOff))
        output.clear()
        terminal.disableRawMode()
        #expect(output.bytes.contains(PointerShapeHost.reset + Terminal.inputModesOff))
        output.clear()
        terminal.showPointerShape(.link)
        #expect(output.bytes.isEmpty, "the shell has the terminal now")
    }

    @Test("An app that has sent no shape is sent no reset as it leaves, and owes a signal none")
    func noResetUntilAShapeIsSent() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        terminal.applyMouseSupport(.full)
        terminal.showPointerShape(nil)
        #expect(!terminal.signalDebt.contains("\u{1B}]22;"))
        output.clear()
        terminal.disableRawMode()
        #expect(!output.bytes.contains("\u{1B}]22;"), "a quit or a suspend wrote a reset nothing asked for")
        terminal.enableRawMode()
        terminal.showPointerShape(.link)
        #expect(terminal.signalDebt.contains(PointerShapeHost.reset + Terminal.inputModesOff))
        terminal.disableRawMode()
        terminal.enableRawMode()
        #expect(!terminal.signalDebt.contains("\u{1B}]22;"), "the suspend's reset paid it; nothing is owed until a shape is sent")
    }

    @Test("After a suspend's reset, the resume sends the shape again")
    func resentOnResume() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        terminal.showPointerShape(.link)
        terminal.disableRawMode()
        terminal.enableRawMode()
        output.clear()
        terminal.showPointerShape(.link)
        #expect(output.bytes == Self.osc22("pointer"))
    }

    @Test("iTerm2 is spoken to in its own names, and a shape it has none for gives its own pointer")
    func iTerm2Names() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(
            environment: ["TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.6.11"])
        terminal.enableRawMode()
        output.clear()
        terminal.showPointerShape(.link)
        #expect(output.bytes == Self.osc22("hand2"))
        output.clear()
        terminal.showPointerShape(.grab)
        #expect(output.bytes == Self.osc22(""), "no open hand on iTerm2: its own pointer, not the hand left over")
    }

    @Test(
        "A terminal not documented to take OSC 22 is sent nothing and owed nothing",
        arguments: [
            ["TERM_PROGRAM": "Apple_Terminal"], ["TERM_PROGRAM": "WarpTerminal"], ["TERM_PROGRAM": "tmux"],
            ["TERM": "xterm-256color"], ["TERM_PROGRAM": "ghostty", "TUIKIT_POINTER_SHAPES": "0"],
        ])
    func inertElsewhere(environment: [String: String]) {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: environment)
        #expect(terminal.pointerShapeHost == nil)
        terminal.enableRawMode()
        terminal.applyMouseSupport(.full)
        terminal.showPointerShape(.link)
        terminal.disableRawMode()
        #expect(!output.bytes.contains("\u{1B}]22;"))
        #expect(!terminal.signalDebt.contains("\u{1B}]22;"))
    }
}
