//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TerminalOutputTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
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

// MARK: - Raw mode

extension TerminalOutputTests {

    /// K2 in `Documentation/Ghostty-VT-adoption.md`: a scrolling region or
    /// origin mode left by a killed program offsets or clamps every absolute
    /// cursor move a frame makes, and application cursor keys or keypad
    /// change what the keys send.
    @Test("Raw mode asserts the inherited defaults, turns autowrap off and the input modes on, and nothing else")
    func enableRawModeBytes() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        #expect(output.bytes == "\u{1B}[r\u{1B}[?6l\u{1B}[?1l\u{1B}>" + "\u{1B}[?7l"
            + "\u{1B}[?2004h" + "\u{1B}[?1004h" + "\u{1B}[?2031h" + "\u{1B}[>1;2m")
    }

    /// K3 in `Documentation/Ghostty-VT-adoption.md`: a host that advances a
    /// cluster further than TUIkit counted wrapped the row into the next one,
    /// and on the bottom row scrolled the screen. Off while the app runs; on
    /// again for whatever the terminal is handed to.
    @Test("Autowrap is put back on by the teardown, on a suspend, and in the debt a fatal signal pays")
    func autowrapIsRestoredOnEveryWayOut() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        #expect(terminal.signalDebt.contains("\u{1B}[?7h"))
        output.clear()
        terminal.disableRawMode()
        #expect(output.writes.first == "\u{1B}[?2026l\u{1B}[?7h", "before anything else")

        // A resume turns it off again, as a startup does.
        output.clear()
        terminal.enableRawMode()
        #expect(output.bytes.contains("\u{1B}[?7l"))

        let (quiet, _) = ScriptedTerminalOutput.terminal(environment: ["TUIKIT_SYNCHRONIZED_OUTPUT": "0"])
        #expect(quiet.outputModesOff == "\u{1B}[?7h", "owed whether or not frames are held")
    }

    /// Raw mode is entered before the terminal is identified, so what it
    /// sends reaches Apple Terminal whether or not it is known to be there.
    @Test("Nothing raw mode sends is a shape Apple Terminal prints")
    func enableRawModeIsAppleSafe() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        terminal.disableRawMode()
        #expect(csiSequencesAppleTerminalLeaks(in: output.bytes).isEmpty)
        #expect(stringIntroducersAppleTerminalPrints(in: output.bytes).isEmpty)
    }
}

// MARK: - The frame dump

extension TerminalOutputTests {

    /// Ghostty's VT reference, K6 in `Documentation/Ghostty-VT-adoption.md`:
    /// `CSI s` is DECSLRM, not a save, while left-right margin mode is on, and
    /// whether `CSI u` restores SGR is up to the terminal. `ESC 7` and `ESC 8`
    /// save and restore both the position and the styling everywhere.
    @Test("The frame dump's notice saves and restores the cursor with DECSC and DECRC")
    func frameDumpNoticeUsesDECSC() throws {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit-frame-dump-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        terminal.dumpLastFrame(inDirectory: directory.path)
        #expect(output.writes == ["\u{1B}7\u{1B}[1;1H\u{1B}[7m[TUIkit] No frame data to dump\u{1B}[0m\u{1B}8"])

        terminal.beginFrame()
        terminal.moveCursor(toRow: 3, column: 1)
        terminal.write("\u{1B}[1mframe")
        terminal.endFrame()
        output.clear()
        terminal.dumpLastFrame(inDirectory: directory.path)

        #expect(output.writes.count == 1, "the notice, and nothing else")
        let notice = try #require(output.writes.first)
        #expect(notice.hasPrefix("\u{1B}7\u{1B}[1;1H\u{1B}[7mFrame dumped → "))
        #expect(notice.hasSuffix("\u{1B}[0m\u{1B}8"))
        #expect(!notice.contains("\u{1B}[s") && !notice.contains("\u{1B}[u"), "no SCOSC or SCORC")

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1)
        let name = try #require(files.first)
        let dumped = try Data(contentsOf: directory.appendingPathComponent(name))
        #expect(dumped == Data("\u{1B}[3;1H\u{1B}[1mframe".utf8), "the frame as it was sent")
    }
}
