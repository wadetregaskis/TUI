//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalHostLedgerOwnerTests.swift
//
//  One ledger of what the app sets on the terminal beyond its screen, and the
//  terminal keeps it: the title a frame sets and the pointer's shape are owed
//  by the terminal they were written to, with nothing to hand the debt over;
//  the terminal arms that debt for a signal again whenever what the ledger
//  owes changes — at once outside a frame, once the frame is out inside one;
//  and whether the progress bar is kept alive is the render loop's to say, on
//  the terminal's ledger (decisions HOSTLEDGER, B-HOSTLEDGER-1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITerminalHost
@testable import TUITestSupport

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
    private static let titleSet = "\u{1B}]2;Notes\u{1B}\\"
    private static let ghostty = ["TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.3.1"]

    @Test("The title a frame sets is owed by the terminal it went to, beside the pointer's shape, until handed back")
    func frameTitleOwedByItsTerminal() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
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

    // The tests below read what the terminal ARMED for a signal (the scripted
    // terminal's `armings`), not `signalDebt`, which is spelled from the ledger
    // whenever it is read and so holds whether or not anything was armed. Every
    // closure is hoisted out of `#expect`/`#require`
    // (Tools/CompilerBugs/MacroClosureDiscriminatorCollision).

    @Test("A frame that saves the title arms its restore for a signal once the frame has gone out, not before")
    func frameTitleArmedOnceTheFrameIsOut() throws {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        let loop = RenderLoopHarness().loop(TitledApp(), on: terminal)
        output.clear()
        _ = loop.render()

        let savesTitle: (String) -> Bool = { $0.contains(Self.titleSet) }
        let frame = try #require(output.writes.firstIndex(where: savesTitle), "the frame sets the title")
        let owesRestore: (ScriptedTerminalOutput.Arming) -> Bool = { $0.signalDebt.contains(Self.restore) }
        let owing = output.armings.filter(owesRestore)
        let afterFrame: (ScriptedTerminalOutput.Arming) -> Bool = { $0.afterWrites > frame }
        let allAfterFrame = owing.allSatisfy(afterFrame)
        #expect(!owing.isEmpty, "the frame's title is armed for a signal")
        #expect(allAfterFrame, "a restore armed before the frame went out would pop a title never saved")
        #expect(output.armedDebt?.contains(Self.restore) == true)
        #expect(output.armings.last?.quitDebt.contains(Self.restore) == true, "and for a SIGQUIT")
    }

    @Test("Outside a frame the ledger is armed at once: the pointer's first shape before its write, a hand-back's restore dropped")
    func armedAtOnceOutsideAFrame() throws {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        let loop = RenderLoopHarness().loop(TitledApp(), on: terminal)
        _ = loop.render()
        output.clear()

        terminal.showPointerShape(.link)
        #expect(output.writes == ["\u{1B}]22;pointer\u{1B}\\"])
        let owesPointer: (ScriptedTerminalOutput.Arming) -> Bool = {
            $0.signalDebt.contains(PointerShapeHost.reset + Terminal.inputModesOff)
        }
        let pointerArming = try #require(output.armings.first(where: owesPointer), "the shape is armed")
        #expect(pointerArming.afterWrites == 0, "owed before the shape is written")
        #expect(pointerArming.signalDebt.contains(Self.restore), "beside the frame's title")

        output.clear()
        #expect(loop.handBackHostState() == Self.restore)
        let armed = try #require(output.armedDebt, "the hand-back arms the debt again")
        #expect(!armed.contains(Self.restore), "the title given back is owed no more")
        #expect(armed.contains(PointerShapeHost.reset), "the pointer is raw mode's to put back")
    }

    @Test("Inside a frame a shape is still owed before it is written, as it goes out ahead of the frame")
    func shapeInsideAFrameArmedBeforeItsWrite() throws {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        let loop = RenderLoopHarness().loop(TitledApp(), on: terminal)
        _ = loop.render()
        output.clear()

        terminal.beginFrame()
        terminal.showPointerShape(.link)
        let isShape: (String) -> Bool = { $0 == "\u{1B}]22;pointer\u{1B}\\" }
        let written = try #require(output.writes.firstIndex(where: isShape), "the shape goes out at once")
        let owesPointer: (ScriptedTerminalOutput.Arming) -> Bool = {
            $0.signalDebt.contains(PointerShapeHost.reset + Terminal.inputModesOff)
        }
        let arming = try #require(output.armings.first(where: owesPointer), "armed inside the frame")
        #expect(arming.afterWrites <= written, "owed before the shape is written")
        terminal.endFrame()
    }

    @Test("A frame that changes nothing the ledger owes arms nothing")
    func unchangedFrameArmsNothing() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: Self.ghostty)
        terminal.enableRawMode()
        let loop = RenderLoopHarness().loop(TitledApp(), on: terminal)
        _ = loop.render()
        output.clear()
        _ = loop.render()
        #expect(output.armings.isEmpty, "the title was already owed")
    }

    @Test("A loop under tmux tells the terminal's ledger not to keep the bar alive", arguments: [true, false])
    func loopDecidesTheKeepAlive(isTmux: Bool) {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        _ = RenderLoopHarness().loop(TitledApp(), on: terminal, isTmux: isTmux)
        #expect(terminal.hostState.keepsProgressAlive == !isTmux)
    }
}
