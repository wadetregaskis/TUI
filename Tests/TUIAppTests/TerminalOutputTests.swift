//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalOutputTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

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

// MARK: - Shift-clicks (XTSHIFTESCAPE)

extension TerminalOutputTests {
    /// The Ghostty study's C5: Shift-clicks go to the app while it reports
    /// the mouse, asked for as reporting comes on and handed back as it goes
    /// off and at the teardown, which a signal is owed too.
    @Test("Mouse reporting asks for Shift-clicks, and hands Shift back when it goes off and at the teardown")
    func shiftEscapeFollowsReporting() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: ["TERM_PROGRAM": "ghostty"])
        terminal.enableRawMode()
        output.clear()
        terminal.applyMouseSupport(.standard)
        #expect(output.bytes.contains("\u{1B}[?1006h") && output.bytes.contains(Terminal.shiftEscapeOn))
        output.clear()
        terminal.applyMouseSupport(.full)
        #expect(output.bytes.contains("\u{1B}[?1003h"))
        #expect(!output.bytes.contains(Terminal.shiftEscapeOn), "asked once, as reporting came on")
        output.clear()
        terminal.applyMouseSupport(.disabled)
        #expect(output.bytes.contains(Terminal.shiftEscapeOff))
        terminal.applyMouseSupport(.standard)
        #expect(terminal.signalDebt.contains(Terminal.shiftEscapeOff), "a signal owes it")
        output.clear()
        terminal.disableRawMode()
        #expect(output.bytes.contains(Terminal.inputModesOff + Terminal.shiftEscapeOff))
    }

    /// `TUI_SHIFT_CLICKS=0`, the user's way back to the terminal's own
    /// Shift-click and Shift-drag; and Apple Terminal, which keeps no Shift
    /// bypass and whose reading of the sequence is unmeasured.
    @Test(
        "Nothing is asked where TUI_SHIFT_CLICKS=0 is set, or on Apple Terminal",
        arguments: [["TERM_PROGRAM": "ghostty", "TUI_SHIFT_CLICKS": "0"], ["TERM_PROGRAM": "Apple_Terminal"]])
    func shiftEscapeWithheld(environment: [String: String]) {
        let (terminal, output) = ScriptedTerminalOutput.terminal(environment: environment)
        terminal.enableRawMode()
        terminal.applyMouseSupport(.standard)
        terminal.applyMouseSupport(.disabled)
        terminal.disableRawMode()
        #expect(!output.bytes.contains(Terminal.shiftEscapeOn))
        #expect(!output.bytes.contains(Terminal.shiftEscapeOff))
        #expect(!terminal.signalDebt.contains(Terminal.shiftEscapeOff))
    }
}

// MARK: - A non-blocking descriptor

extension TerminalOutputTests {

    /// The real syscalls: a non-blocking pipe far smaller than what is
    /// written, drained by a reader on another thread, stands in for a
    /// terminal a crashed program left non-blocking.
    ///
    /// The reader is a thread of its own, not a task: the writer blocks the
    /// thread it runs on while it waits for room, and a detached task's reader
    /// waited for a pool thread that a busy parallel suite had none of, so the
    /// write ran out its deadline (gate g57, 2026-10-19; lane LISTS saw the
    /// same, 83 s against 30).
    @Test("A non-blocking descriptor too small for a write takes all of it as it drains")
    func nonBlockingDescriptorTakesEverything() {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else {
            Issue.record("no pipe")
            return
        }
        let (readEnd, writeEnd) = (ends[0], ends[1])
        defer { close(readEnd) }
        _ = fcntl(writeEnd, F_SETFL, fcntl(writeEnd, F_GETFL) | O_NONBLOCK)
        let payload = [UInt8](repeating: 0x78, count: 1 << 20)
        let drained = DrainedCount()
        let reader = Thread {
            var total = 0
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            while true {
                let count = chunk.withUnsafeMutableBytes { read(readEnd, $0.baseAddress, $0.count) }
                guard count > 0 else { break }
                total += count
            }
            drained.finish(total)
        }
        reader.start()
        // A deadline only so a regression fails rather than hangs.
        let deadline = Date().addingTimeInterval(30)
        let complete = payload.withUnsafeBufferPointer { buffer in
            Terminal.writeAll(
                buffer.baseAddress!, buffer.count, through: { Foundation.write(writeEnd, $0, $1) },
                waitingForRoom: { Terminal.waitForRoom(on: writeEnd, until: deadline) })
        }
        close(writeEnd)
        #expect(complete)
        #expect(drained.wait() == payload.count)
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

    /// K2 in `Documentation/Terminals/Ghostty VT reference adoption study.md`: origin mode left on by a
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

    /// SIGQUIT is the user's quit key's signal, and it leaves the terminal as
    /// a quit does: its debt is the bytes the run loop's teardown writes
    /// (`AppRunner.cleanup`: the styling reset, raw mode off, the cursor
    /// shown, the alternate screen left), in that order, whatever the
    /// teardown owes — the kitty flags, a pinned grapheme mode. A crash's
    /// debt leaves the alternate screen up, for the report on it.
    @Test("A SIGQUIT's debt is the bytes a quit's teardown writes, the alternate screen left with them")
    func quitDebtIsTheTeardown() {
        for (pushed, pinned) in [(false, false), (true, true)] {
            let (terminal, output) = ScriptedTerminalOutput.terminal()
            terminal.enterAlternateScreen()
            terminal.enableRawMode()
            terminal.keyboardFlagsPushed = pushed
            terminal.pinnedGraphemeClustering = pinned
            let owed = terminal.quitDebt
            #expect(!terminal.signalDebt.contains(ANSIRenderer.exitAlternateScreen), "a crash keeps its report up")
            output.clear()
            // What `AppRunner.cleanup` writes: its hand-back, with the styling
            // reset by a diff writer that cannot know the terminal is in the
            // default styling — the reset a SIGQUIT has to pay.
            let diffWriter = FrameDiffWriter()
            terminal.handBack(restoringStyling: { diffWriter.restoreDefaultStyling(on: terminal) })
            #expect(owed == output.bytes, "pushed: \(pushed), pinned: \(pinned)")
            #expect(!terminal.quitDebt.hasSuffix(ANSIRenderer.exitAlternateScreen), "off the alternate screen, nothing to leave")
        }
    }

    /// K3 in `Documentation/Terminals/Ghostty VT reference adoption study.md`: a host that advances a
    /// cluster further than TUI counted wrapped the row into the next one,
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

        let (quiet, _) = ScriptedTerminalOutput.terminal(environment: ["TUI_SYNCHRONIZED_OUTPUT": "0"])
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
        terminal.keepAutowrapIfAppleTerminal(environment: ["TUI_TERM_PROGRAM": "Apple_Terminal"])
        #expect(output.writes == ["\u{1B}[?7h"])
        terminal.keepAutowrapIfAppleTerminal(environment: ["TUI_TERM_PROGRAM": "Apple_Terminal"])
        #expect(output.writes == ["\u{1B}[?7h"], "once")
        terminal.disableRawMode()
        output.clear()
        terminal.enableRawMode()
        #expect(!output.bytes.contains("\u{1B}[?7l"), "a resume leaves it on")
        #expect(output.bytes.contains("\u{1B}[?7h"), "and asserts it")

        let (ghostty, ghosttyOutput) = ScriptedTerminalOutput.terminal()
        ghostty.enableRawMode()
        ghosttyOutput.clear()
        ghostty.keepAutowrapIfAppleTerminal(environment: ["TUI_TERM_PROGRAM": "ghostty"])
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

    /// Ghostty's VT reference, K6 in `Documentation/Terminals/Ghostty VT reference adoption study.md`:
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
        #expect(output.writes == ["\u{1B}7\u{1B}[1;1H\u{1B}[7m[TUI] No frame data to dump\u{1B}[0m\u{1B}8"])

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
                "\u{1B}7\u{1B}[?7h\u{1B}[1;1H\u{1B}[7m[TUI] No frame data to dump\u{1B}[0m\u{1B}[?7l\u{1B}8"
            ])

        let (apple, appleOutput) = ScriptedTerminalOutput.terminal(environment: ["TERM_PROGRAM": "Apple_Terminal"])
        apple.enableRawMode()
        appleOutput.clear()
        apple.dumpLastFrame(inDirectory: FileManager.default.temporaryDirectory.path)
        #expect(
            appleOutput.writes == ["\u{1B}7\u{1B}[1;1H\u{1B}[7m[TUI] No frame data to dump\u{1B}[0m\u{1B}8"],
            "where autowrap stays on there is nothing to put back")
    }
}

/// What a reader thread drained, handed to the test when it finishes.
private final class DrainedCount: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var total = 0

    /// Called once, on the reader's thread, with everything it read.
    func finish(_ total: Int) {
        self.total = total
        done.signal()
    }

    /// Blocks until the reader has finished, then returns what it read. The
    /// semaphore orders the write before this read.
    func wait() -> Int {
        done.wait()
        return total
    }
}
