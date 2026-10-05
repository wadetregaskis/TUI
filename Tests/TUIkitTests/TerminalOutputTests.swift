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
