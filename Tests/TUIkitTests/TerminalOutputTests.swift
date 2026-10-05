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

// MARK: - A non-blocking descriptor

extension TerminalOutputTests {

    /// The real syscalls: a non-blocking pipe far smaller than what is
    /// written, drained by a reader on another thread, stands in for a
    /// terminal a crashed program left non-blocking.
    @Test("A non-blocking descriptor too small for a write takes all of it as it drains")
    func nonBlockingDescriptorTakesEverything() async {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else {
            Issue.record("no pipe")
            return
        }
        let (readEnd, writeEnd) = (ends[0], ends[1])
        defer { close(readEnd) }
        _ = fcntl(writeEnd, F_SETFL, fcntl(writeEnd, F_GETFL) | O_NONBLOCK)
        let payload = [UInt8](repeating: 0x78, count: 1 << 20)
        let reader = Task.detached { () -> Int in
            var total = 0
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            while true {
                let count = chunk.withUnsafeMutableBytes { read(readEnd, $0.baseAddress, $0.count) }
                guard count > 0 else { return total }
                total += count
            }
        }
        // A deadline only so a regression fails rather than hangs.
        let deadline = Date().addingTimeInterval(30)
        let complete = payload.withUnsafeBufferPointer { buffer in
            Terminal.writeAll(
                buffer.baseAddress!, buffer.count, through: { Foundation.write(writeEnd, $0, $1) },
                waitingForRoom: { Terminal.waitForRoom(on: writeEnd, until: deadline) })
        }
        close(writeEnd)
        #expect(complete)
        #expect(await reader.value == payload.count)
    }

    @Test("Waiting for room on a full descriptor nobody drains gives up at its deadline")
    func waitForRoomGivesUp() {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else {
            Issue.record("no pipe")
            return
        }
        defer { close(ends[0]); close(ends[1]) }
        _ = fcntl(ends[1], F_SETFL, fcntl(ends[1], F_GETFL) | O_NONBLOCK)
        #expect(Terminal.waitForRoom(on: ends[1], until: Date().addingTimeInterval(1)), "an empty pipe has room")
        var byte: UInt8 = 0x78
        while Foundation.write(ends[1], &byte, 1) == 1 {}
        #expect(!Terminal.waitForRoom(on: ends[1], until: Date().addingTimeInterval(0.05)))
    }
}

// MARK: - Raw mode

extension TerminalOutputTests {

    /// K2 in `Documentation/Ghostty-VT-adoption.md`: origin mode left on by a
    /// killed program offsets or clamps every absolute cursor move a frame
    /// makes into the region it left, left-right margins stop every row at
    /// the right margin, and application cursor keys or keypad change what
    /// the keys send.
    @Test("Raw mode asserts the inherited defaults, turns autowrap off and the input modes on, and nothing else")
    func enableRawModeBytes() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        #expect(output.bytes == "\u{1B}[r\u{1B}[?69l\u{1B}[?6l\u{1B}[?1l\u{1B}>" + "\u{1B}[?7l"
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

    /// K3's precondition: Apple Terminal's card decides, so until it is run
    /// that host keeps the terminal's default, at startup and on every resume.
    @Test("Apple Terminal, named by the environment, runs with autowrap on, which raw mode turns on")
    func appleTerminalKeepsAutowrap() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: ["TERM_PROGRAM": "Apple_Terminal"])
        terminal.enableRawMode()
        #expect(
            output.bytes.hasPrefix(Terminal.inheritedDefaults + "\u{1B}[?7h" + "\u{1B}[?2004h"),
            "the defaults, and autowrap asserted on: a killed program may have left it off")
        #expect(!output.bytes.contains("\u{1B}[?7l"))
        terminal.disableRawMode()
        output.clear()
        terminal.enableRawMode()
        #expect(output.bytes.contains("\u{1B}[?7h"), "and again on a resume")
        #expect(!output.bytes.contains("\u{1B}[?7l"), "never off")
    }

    /// Over ssh nothing in the environment names the host, so raw mode has
    /// turned autowrap off before the startup exchange answers.
    @Test("Apple Terminal named by the startup exchange gets autowrap back on at once, and keeps it")
    func appleTerminalNamedLateGetsAutowrapBack() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        #expect(output.bytes.contains("\u{1B}[?7l"))
        output.clear()
        terminal.keepAutowrapIfAppleTerminal(environment: ["TUIKIT_TERM_PROGRAM": "Apple_Terminal"])
        #expect(output.writes == ["\u{1B}[?7h"])
        terminal.keepAutowrapIfAppleTerminal(environment: ["TUIKIT_TERM_PROGRAM": "Apple_Terminal"])
        #expect(output.writes == ["\u{1B}[?7h"], "once")
        terminal.disableRawMode()
        output.clear()
        terminal.enableRawMode()
        #expect(!output.bytes.contains("\u{1B}[?7l"), "a resume leaves it on")
        #expect(output.bytes.contains("\u{1B}[?7h"), "and asserts it")

        let (ghostty, ghosttyOutput) = ScriptedTerminalOutput.terminal()
        ghostty.enableRawMode()
        ghosttyOutput.clear()
        ghostty.keepAutowrapIfAppleTerminal(environment: ["TUIKIT_TERM_PROGRAM": "ghostty"])
        #expect(ghosttyOutput.writes.isEmpty, "another host keeps it off")
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

    /// With autowrap off, a notice wider than the screen — the dump's path in
    /// a deep working directory — lost its file name at the right edge.
    @Test("The frame dump's notice wraps while the app runs with autowrap off, and leaves it off")
    func frameDumpNoticeWraps() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        output.clear()
        terminal.dumpLastFrame(inDirectory: FileManager.default.temporaryDirectory.path)
        #expect(
            output.writes == [
                "\u{1B}7\u{1B}[?7h\u{1B}[1;1H\u{1B}[7m[TUIkit] No frame data to dump\u{1B}[0m\u{1B}[?7l\u{1B}8"
            ])

        let (apple, appleOutput) = ScriptedTerminalOutput.terminal(environment: ["TERM_PROGRAM": "Apple_Terminal"])
        apple.enableRawMode()
        appleOutput.clear()
        apple.dumpLastFrame(inDirectory: FileManager.default.temporaryDirectory.path)
        #expect(
            appleOutput.writes == ["\u{1B}7\u{1B}[1;1H\u{1B}[7m[TUIkit] No frame data to dump\u{1B}[0m\u{1B}8"],
            "where autowrap stays on there is nothing to put back")
    }
}
