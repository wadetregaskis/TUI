//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SynchronizedOutputTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitCore
@testable import TUIkitFoundation

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
        #expect(output.writes.first?.hasPrefix(Self.end) == true)
    }

    #if !canImport(WASILibc)
    @Test("The longest debts fit the buffers a signal handler writes from")
    func debtFits() {
        let (terminal, _) = ScriptedTerminalOutput.terminal()
        terminal.enterAlternateScreen()
        terminal.enableRawMode()
        terminal.keyboardFlagsPushed = true
        terminal.pinnedGraphemeClustering = true
        #expect(terminal.signalDebt.utf8.count <= FatalSignalTerminalRestore.capacity)
        #expect(terminal.quitDebt.utf8.count <= FatalSignalTerminalRestore.capacity)

        // And a quit's, the deletes for more images than its farewell holds.
        let images = TerminalImageStore()
        for index in 0..<400 {
            _ = images.placeholderRows(
                token: "t\(index)",
                signature: TerminalImageSignature(
                    source: .file("s\(index)"), rawWidth: 1, rawHeight: 1, pixelWidth: 1, pixelHeight: 1,
                    colorMode: .trueColor, toneCurve: nil, edgeContrast: 0, dithering: .none,
                    monoInk: RGBA(r: 255, g: 255, b: 255), monoPaper: RGBA(r: 0, g: 0, b: 0),
                    terminalColors: .unknown),
                columns: 1, rows: 1, pixels: { ([0x80, 0x80, 0x80, 0xFF], .rgba, 1, 1) })
        }
        terminal.oweFarewell(for: images)
        #expect(terminal.quitFarewell.utf8.count > Terminal.quitFarewellCapacity - 32, "filled")
        #expect(terminal.quitFarewell.utf8.count <= Terminal.quitFarewellCapacity)
        #expect(terminal.quitDebt.utf8.count <= FatalSignalTerminalRestore.quitCapacity)
        terminal.keyboardFlagsPushed = false
    }
    #endif

    /// `write` that takes `firstWrite` bytes, then fails with `error` (`EIO`
    /// unless a test says otherwise) `times` times, then takes everything,
    /// recording what it took.
    private final class FlakyOutput {
        let firstWrite: Int
        let error: Int32
        let times: Int
        var taken: [UInt8] = []
        var calls = 0

        init(firstWrite: Int, failingWith error: Int32 = EIO, times: Int = 1) {
            self.firstWrite = firstWrite
            self.error = error
            self.times = times
        }

        func write(_ base: UnsafePointer<UInt8>, _ count: Int) -> Int {
            calls += 1
            let length: Int
            switch calls {
            case 1: length = min(count, firstWrite)
            case 2...(1 + times):
                errno = error
                return -1
            default: length = count
            }
            taken.append(contentsOf: UnsafeBufferPointer(start: base, count: length))
            return length
        }
    }

    /// A descriptor a crashed program left non-blocking reports `EAGAIN` when
    /// full, and the end marker's retry right after met the same. The hold
    /// then lasted until the next multi-row frame: a caret's blink or a
    /// breath writes one row and no end marker.
    @Test("A held frame on a full non-blocking descriptor waits for room and goes out whole, end marker and all")
    func fullNonBlockingDescriptorWaits() {
        let frame = Array((Self.begin + "\u{1B}[1;1Hx\u{1B}[2;1Hx" + Self.end).utf8)
        let output = FlakyOutput(firstWrite: 12, failingWith: EAGAIN, times: 2)
        var waits = 0
        frame.withUnsafeBufferPointer { buffer in
            Terminal.writeFrame(
                buffer, omitting: nil, holdsDisplay: true, through: output.write,
                waitingForRoom: {
                    waits += 1
                    return true
                })
        }
        #expect(output.taken == frame, "every byte once, in order")
        #expect(waits == 2, "once per EAGAIN")

        let stuck = FlakyOutput(firstWrite: 12, failingWith: EAGAIN, times: 1)
        frame.withUnsafeBufferPointer { buffer in
            Terminal.writeFrame(
                buffer, omitting: nil, holdsDisplay: true, through: stuck.write, waitingForRoom: { false })
        }
        #expect(
            stuck.taken == Array(frame.prefix(12)) + Array(Self.end.utf8),
            "a wait that gives up is a failed write: the end marker follows on its own")
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
