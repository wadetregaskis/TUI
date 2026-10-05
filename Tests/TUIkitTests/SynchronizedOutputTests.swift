//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SynchronizedOutputTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit
@testable import TUIkitCore

/// A frame that writes more than one row holds the terminal's display while
/// it is drawn (DEC mode 2026), and nothing else does. Step V2 of the Ghostty
/// adoption (`Documentation/Ghostty-VT-adoption.md`, O1).
@MainActor
@Suite("Synchronized output (DEC mode 2026)")
struct SynchronizedOutputTests {

    private static let begin = "\u{1B}[?2026h"
    private static let end = "\u{1B}[?2026l"

    /// One frame: `transmissions` first, as the render loop writes pending
    /// images, then the hold's begin, then an `x` at column 1, 5, 9… of each
    /// of `rows`.
    private func frame(on terminal: Terminal, transmissions: String = "", rows: [Int], spansPerRow: Int = 1) {
        terminal.beginFrame()
        if !transmissions.isEmpty { terminal.write(transmissions) }
        terminal.beginSynchronizedUpdate()
        for row in rows {
            for span in 0..<spansPerRow {
                terminal.moveCursor(toRow: row, column: 1 + span * 4)
                terminal.write("x")
            }
        }
        terminal.endFrame()
    }

    @Test("A frame that writes more than one row is held once, in the one write that sends it")
    func multiRowFrameIsHeld() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        frame(on: terminal, rows: [2, 3])
        #expect(output.writes == [Self.begin + "\u{1B}[2;1Hx\u{1B}[3;1Hx" + Self.end])
        #expect(terminal.lastFrameData == Array(output.bytes.utf8), "the frame dump sees what was sent")
    }

    @Test("A frame that writes one row, in however many spans, is not held")
    func singleRowFrameIsNotHeld() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        frame(on: terminal, rows: [5], spansPerRow: 3)
        #expect(output.writes == ["\u{1B}[5;1Hx\u{1B}[5;5Hx\u{1B}[5;9Hx"])
        #expect(terminal.lastFrameData == Array(output.bytes.utf8))
    }

    @Test("A frame that writes nothing sends nothing")
    func emptyFrameWritesNothing() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        frame(on: terminal, rows: [])
        #expect(output.writes.isEmpty)
    }

    @Test("Image transmissions go before the hold, and an unheld frame goes out either side of its unused marker")
    func transmissionsStayOutsideTheHold() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        let graphics = "\u{1B}_Ga=t,i=1;AAAA\u{1B}\\"
        frame(on: terminal, transmissions: graphics, rows: [1, 2])
        #expect(output.writes == [graphics + Self.begin + "\u{1B}[1;1Hx\u{1B}[2;1Hx" + Self.end])

        output.clear()
        frame(on: terminal, transmissions: graphics, rows: [1])
        #expect(output.writes == [graphics, "\u{1B}[1;1Hx"])
        #expect(terminal.lastFrameData == Array((graphics + "\u{1B}[1;1Hx").utf8))
    }

    @Test("TUIKIT_SYNCHRONIZED_OUTPUT=0 holds nothing, and owes nothing")
    func offSwitch() {
        let (terminal, output) = ScriptedTerminalOutput.terminal(
            environment: ["TUIKIT_SYNCHRONIZED_OUTPUT": "0"])
        frame(on: terminal, rows: [1, 2, 3])
        #expect(output.writes == ["\u{1B}[1;1Hx\u{1B}[2;1Hx\u{1B}[3;1Hx"])
        #expect(!terminal.signalDebt.contains(Self.end))
        #expect(Terminal.synchronizedOutputAllowed(environment: [:]))
        #expect(Terminal.synchronizedOutputAllowed(environment: ["TUIKIT_SYNCHRONIZED_OUTPUT": "1"]))
    }

    @Test("The end marker is the first thing the teardown sends, and leads the debt a fatal signal pays")
    func endMarkerInTeardownAndDebt() {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        #expect(terminal.signalDebt.hasPrefix(Self.end))
        output.clear()
        terminal.disableRawMode()
        #expect(output.writes.first == Self.end)
    }

    #if !canImport(WASILibc)
    @Test("The longest debt fits the buffer a signal handler writes from")
    func debtFits() {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        terminal.enableRawMode()
        terminal.keyboardFlagsPushed = true
        terminal.pinnedGraphemeClustering = true
        #expect(terminal.signalDebt.utf8.count <= FatalSignalTerminalRestore.capacity)
        terminal.keyboardFlagsPushed = false
    }
    #endif

    /// `write` that takes `firstWrite` bytes, then fails with `EIO`, then
    /// takes everything, recording what it took.
    private final class FlakyOutput {
        let firstWrite: Int
        var taken: [UInt8] = []
        var calls = 0

        init(firstWrite: Int) { self.firstWrite = firstWrite }

        func write(_ base: UnsafePointer<UInt8>, _ count: Int) -> Int {
            calls += 1
            let length: Int
            switch calls {
            case 1: length = min(count, firstWrite)
            case 2:
                errno = EIO
                return -1
            default: length = count
            }
            taken.append(contentsOf: UnsafeBufferPointer(start: base, count: length))
            return length
        }
    }

    @Test("A write that gives up partway through a held frame is followed by the end marker on its own")
    func failedWriteLetsGo() {
        let frame = Array((Self.begin + "\u{1B}[1;1Hx\u{1B}[2;1Hx" + Self.end).utf8)
        let output = FlakyOutput(firstWrite: 12)
        frame.withUnsafeBufferPointer { buffer in
            Terminal.writeFrame(buffer, omitting: nil, holdsDisplay: true, through: output.write)
        }
        #expect(output.taken == Array(frame.prefix(12)) + Array(Self.end.utf8))

        let unheld = Array("\u{1B}[1;1Hx".utf8)
        let quiet = FlakyOutput(firstWrite: 3)
        unheld.withUnsafeBufferPointer { buffer in
            Terminal.writeFrame(buffer, omitting: nil, holdsDisplay: false, through: quiet.write)
        }
        #expect(quiet.taken == Array(unheld.prefix(3)), "a frame that held nothing owes nothing")
    }

    @Test("A rendered frame's hold begins after its image transmissions and before its first cell")
    func renderLoopHoldsAfterTransmissions() throws {
        let (terminal, output) = ScriptedTerminalOutput.terminal()
        let harness = RenderLoopHarness()
        let loop = harness.loop(PictureApp(), on: terminal)
        KittyGraphics.withSupport(true) { _ = loop.render() }

        let bytes = output.bytes
        let transmission = try #require(bytes.range(of: "a=t,"), "the frame sends its picture")
        let hold = try #require(bytes.range(of: Self.begin))
        let firstMove = try #require(bytes.range(of: "\u{1B}\\[[0-9]+;[0-9]+H", options: .regularExpression))
        #expect(transmission.upperBound <= hold.lowerBound)
        #expect(hold.upperBound <= firstMove.lowerBound)
        #expect(bytes.hasSuffix(Self.end))
        #expect(bytes.components(separatedBy: Self.begin).count == 2, "held once")
    }
}

/// A picture above a line of text: a frame of several rows that transmits an
/// image where the terminal draws them.
private struct PictureApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)], startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 10, height: 2)
                Text("below")
            }
        }
    }
}
