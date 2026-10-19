//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalHostLedgerOwnerTests.swift
//
//  One ledger of what the app sets on the terminal beyond its screen, and the
//  terminal keeps it: the title a frame sets and the pointer's shape are owed
//  by the terminal they were written to, with nothing to hand the debt over;
//  and whether the progress bar is kept alive is the render loop's to say, on
//  the terminal's ledger (decisions HOSTLEDGER, B-HOSTLEDGER-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitTerminalHost
@testable import TUIkitTestSupport

/// A window whose scene's title is the terminal's.
private struct TitledApp: App {
    init() {}
    var body: some Scene {
        WindowGroup("Notes") { Text("notes window") }
    }
}

@MainActor
@Suite("The terminal keeps the host ledger")
struct TerminalHostLedgerOwnerTests {
    private static let restore = "\u{1B}[23;2t"

    @Test("The title a frame sets is owed by the terminal it went to, beside the pointer's shape, until handed back")
    func frameTitleOwedByItsTerminal() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(
            environment: ["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.3.1"])
        terminal.enableRawMode()
        let loop = RenderLoopHarness().loop(TitledApp(), on: terminal)
        _ = loop.render()
        #expect(output.bytes.contains("\u{1B}]2;Notes\u{1B}\\"))
        #expect(terminal.hostState.writtenTitle == "Notes")
        #expect(terminal.signalDebt.contains(Self.restore), "the frame's title is owed with nothing to hand it over")

        terminal.showPointerShape(.link)
        let debt = terminal.signalDebt
        #expect(debt.contains(PointerShapeHost.reset + Terminal.inputModesOff))
        #expect(debt.contains(Self.restore))

        #expect(loop.handBackHostState() == Self.restore)
        #expect(!terminal.signalDebt.contains(Self.restore))
        #expect(terminal.signalDebt.contains(PointerShapeHost.reset), "the pointer is raw mode's to put back")
    }

    @Test("A loop under tmux tells the terminal's ledger not to keep the bar alive", arguments: [true, false])
    func loopDecidesTheKeepAlive(isTmux: Bool) {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        _ = RenderLoopHarness().loop(TitledApp(), on: terminal, isTmux: isTmux)
        #expect(terminal.hostState.keepsProgressAlive == !isTmux)
    }
}
