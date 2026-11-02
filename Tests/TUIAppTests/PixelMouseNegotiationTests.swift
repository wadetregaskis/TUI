//  🖥️ TUI — A Terminal UI framework for Swift
//  PixelMouseNegotiationTests.swift
//
//  SGR-Pixels: what is asked of whom, when reports change meaning, and that a
//  pixel report comes out at the whole cell the terminal itself says it is in.
//  The pairs of reports are measured (`Tools/TerminalProbes/pixel_mouse_probe.py`,
//  `data/*-pixel-mouse.json`): the same physical click, once in each mode.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITerminalHost

private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

private let ghostty = PixelMouseNegotiation.Host(countsFromZero: true, cellSource: .cellReply)
private let iTerm2 = PixelMouseNegotiation.Host(cellSource: .cellReply, answersThroughSGRMode: true)

private extension PixelMouseNegotiation {
    /// `update` for a frame with this grid.
    mutating func frame(
        wanted: Bool, grid: (width: Int, height: Int), host: Host?, cellReading: TerminalCellPixels? = nil
    ) -> String {
        update(wanted: wanted, grid: grid, cellReading: cellReading, host: host)
    }

    /// Asked, answered and turned on, as Ghostty 1.4.0 and iTerm2 3.7.6 answered.
    mutating func negotiate(
        _ host: Host, grid: (width: Int, height: Int), cell: (width: Int, height: Int),
        area: (width: Int, height: Int)? = nil
    ) {
        _ = frame(wanted: true, grid: grid, host: host)
        _ = hear(bytes("\u{1B}[6;\(cell.height);\(cell.width)t"))
        if let area { _ = hear(bytes("\u{1B}[4;\(area.height);\(area.width)t")) }
        let support = host.answersThroughSGRMode ? "4" : "2"
        _ = hear(bytes("\u{1B}[?1016;\(support)$y"))
        let on = host.stateWithPixelsOn.rawValue
        _ = hear(bytes("\u{1B}[?\(host.fenceMode);\(on)$y"))
    }

    /// A report in the terminal's own numbers, through the parser and this.
    mutating func read(_ x: Int, _ y: Int, final: String = "M", code: Int = 0) -> MouseEvent? {
        guard let parsed = MouseEvent.parseSGR(bytes("\u{1B}[<\(code);\(x);\(y)\(final)")) else { return nil }
        return convert(parsed).event
    }
}

@Suite("The pixel mouse's negotiation")
struct PixelMouseNegotiationTests {
    // MARK: Whom it asks

    @Test("Only a host that answers DECRQM and may have the mode is asked")
    func whoIsAsked() {
        let of = PixelMouseNegotiation.Host.of
        #expect(of(.ghostty, [:]) == ghostty)
        #expect(of(.iTerm2, [:]) == iTerm2)
        #expect(of(.xtermJS, [:])?.cellSource == .areaOverGrid)
        for silent in [TerminalClient.Program.appleTerminal, .warp, .gnomeTerminal, .tmux] {
            #expect(of(silent, [:]) == nil)
        }
        #expect(of(.unidentified, [:]) == nil, "it might print the question")
        #expect(of(.unidentified, ["TERM": "xterm-kitty"])?.cellSource == .agreement)
        #expect(of(.unidentified, ["XTERM_VERSION": "XTerm(390)"])?.cellSource == .agreement)
        #expect(of(.ghostty, ["TUI_PIXEL_MOUSE": "0"]) == nil)
    }

    @Test("Nothing is written, or asked, until something on screen wants it")
    func nothingUnasked() {
        var negotiation = PixelMouseNegotiation()
        #expect(negotiation.frame(wanted: false, grid: (80, 24), host: ghostty).isEmpty)
        #expect(negotiation.phase == .idle)
        #expect(!negotiation.isListening)
    }

    // MARK: When reports change meaning

    @Test("Reports stay cells until the reply that follows the mode's change")
    func fencedOn() {
        var negotiation = PixelMouseNegotiation()
        #expect(negotiation.frame(wanted: true, grid: (56, 19), host: ghostty) == "\u{1B}[16t\u{1B}[14t\u{1B}[?1016$p")
        #expect(negotiation.hear(bytes("\u{1B}[6;34;16t"))?.isEmpty == true)
        #expect(negotiation.hear(bytes("\u{1B}[4;646;896t"))?.isEmpty == true)
        #expect(negotiation.hear(bytes("\u{1B}[?1016;2$y")) == "\u{1B}[?1016h\u{1B}[?1016$p")
        #expect(!negotiation.readsPixels, "a report already in the pipe is in cells")
        #expect(negotiation.holdsPixels)
        #expect(negotiation.hear(bytes("\u{1B}[?1016;1$y"))?.isEmpty == true)
        #expect(negotiation.readsPixels)
    }

    @Test("Going back, reports stay pixels until the reply, and `?1006` comes back with them")
    func fencedOff() {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (16, 34))
        #expect(negotiation.frame(wanted: false, grid: (56, 19), host: ghostty) == "\u{1B}[?1016l\u{1B}[?1006h\u{1B}[?1016$p")
        #expect(negotiation.readsPixels)
        #expect(!negotiation.holdsPixels)
        _ = negotiation.hear(bytes("\u{1B}[?1016;2$y"))
        #expect(!negotiation.readsPixels)
        #expect(negotiation.phase == .off)
        #expect(negotiation.frame(wanted: true, grid: (56, 19), host: ghostty) == "\u{1B}[?1016h\u{1B}[?1016$p", "nothing asked twice")
    }

    @Test("iTerm2 says no to `?1016` and yes by what `?1006` does")
    func iTerm2Fence() {
        var negotiation = PixelMouseNegotiation()
        _ = negotiation.frame(wanted: true, grid: (80, 25), host: iTerm2)
        _ = negotiation.hear(bytes("\u{1B}[6;17;7t"))
        #expect(negotiation.hear(bytes("\u{1B}[?1016;4$y")) == "\u{1B}[?1016h\u{1B}[?1006$p")
        _ = negotiation.hear(bytes("\u{1B}[?1006;2$y"))
        #expect(negotiation.readsPixels)

        var old = PixelMouseNegotiation()
        _ = old.frame(wanted: true, grid: (80, 25), host: iTerm2)
        _ = old.hear(bytes("\u{1B}[6;17;7t"))
        _ = old.hear(bytes("\u{1B}[?1016;4$y"))
        _ = old.hear(bytes("\u{1B}[?1006;1$y"))
        #expect(old.phase == .unavailable, "the mode did not take: cells, as before")
    }

    @Test("No mode, no cell size or no answer at all leaves cell reports")
    func fallsBack() {
        var noMode = PixelMouseNegotiation()
        _ = noMode.frame(wanted: true, grid: (80, 24), host: ghostty)
        _ = noMode.hear(bytes("\u{1B}[6;34;16t"))
        #expect(noMode.hear(bytes("\u{1B}[?1016;0$y"))?.isEmpty == true)
        #expect(noMode.phase == .unavailable)

        var noCell = PixelMouseNegotiation()
        _ = noCell.frame(wanted: true, grid: (80, 24), host: ghostty)
        #expect(noCell.hear(bytes("\u{1B}[?1016;2$y"))?.isEmpty == true, "xterm.js as the demo configures it answers neither 14 t nor 16 t")
        #expect(noCell.phase == .unavailable)

        var silence = PixelMouseNegotiation()
        _ = silence.frame(wanted: true, grid: (80, 24), host: ghostty)
        #expect(!silence.readsPixels)
        let report = MouseEvent(button: .left, phase: .pressed, x: 3, y: 4)
        #expect(silence.phase == .asked)
        #expect(!silence.holdsPixels)
        #expect(report.subcellX == 0)
    }

    @Test("A resize or a font change asks the cell's size again, and only then")
    func geometryMoved() {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (16, 34))
        #expect(negotiation.frame(wanted: true, grid: (56, 19), host: ghostty).isEmpty)
        #expect(negotiation.frame(wanted: true, grid: (40, 19), host: ghostty) == "\u{1B}[16t\u{1B}[14t")
        #expect(negotiation.frame(wanted: true, grid: (40, 19), host: ghostty).isEmpty)
        let bigger = TerminalCellPixels(width: 20, height: 40)
        #expect(negotiation.frame(wanted: true, grid: (40, 19), host: ghostty, cellReading: bigger) == "\u{1B}[16t\u{1B}[14t")
        _ = negotiation.hear(bytes("\u{1B}[6;40;20t"))
        #expect(negotiation.read(45, 45)?.x == 2)
    }

    @Test("Tracking turned off gives pixels back with no question for the shell to read")
    func trackingOff() {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (16, 34))
        let write = negotiation.update(wanted: false, tracking: false, grid: (56, 19), cellReading: nil, host: ghostty)
        #expect(write == "\u{1B}[?1016l")
        #expect(negotiation.phase == .off)
        #expect(!negotiation.readsPixels)
    }

    @Test("After a suspend the terminal is in cells again, and nothing is believed owed")
    func suspend() {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (16, 34))
        negotiation.noteModesReset()
        #expect(!negotiation.readsPixels)
        #expect(negotiation.phase == .off)
        #expect(negotiation.frame(wanted: true, grid: (56, 19), host: ghostty) == "\u{1B}[?1016h\u{1B}[?1016$p")
    }

    // MARK: Whole cells

    @Test("Ghostty 1.4.0's pixel reports land in the cell its cell reports name", arguments: [
        (cell: (17, 19), pixel: (266, 632)), (cell: (16, 9), pixel: (252, 282)), (cell: (27, 9), pixel: (426, 292)),
        (cell: (33, 15), pixel: (514, 490)), (cell: (19, 4), pixel: (292, 124)), (cell: (28, 12), pixel: (432, 382)),
    ])
    func measuredGhostty(_ pair: (cell: (Int, Int), pixel: (Int, Int))) {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (16, 34))
        let event = negotiation.read(pair.pixel.0, pair.pixel.1)
        #expect(event?.x == pair.cell.0 - 1)
        #expect(event?.y == pair.cell.1 - 1)
    }

    @Test("iTerm2 3.7.6's pixel reports land in the cell its cell reports name", arguments: [
        (cell: (24, 25), pixel: (163, 410)), (cell: (23, 11), pixel: (155, 177)), (cell: (38, 11), pixel: (265, 184)),
        (cell: (46, 19), pixel: (320, 315)), (cell: (26, 5), pixel: (179, 73)), (cell: (39, 15), pixel: (269, 243)),
    ])
    func measuredITerm2(_ pair: (cell: (Int, Int), pixel: (Int, Int))) {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(iTerm2, grid: (80, 25), cell: (7, 17))
        let event = negotiation.read(pair.pixel.0, pair.pixel.1)
        #expect(event?.x == pair.cell.0 - 1)
        #expect(event?.y == pair.cell.1 - 1)
    }

    @Test("What is left over is the fraction across the cell")
    func fractions() {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (16, 34))
        let event = negotiation.read(40, 51)
        #expect(event?.x == 2)
        #expect(event?.y == 1)
        #expect(event?.subcellX == 0.5)
        #expect(event?.subcellY == 0.5)
        #expect(event?.preciseX == 2.5)
    }

    @Test("A press past the grid proves the size wrong: dropped, and pixels given back for good")
    func pressOffGrid() {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (8, 17))
        let parsed = MouseEvent.parseSGR(bytes("\u{1B}[<0;800;100M"))
        let result = negotiation.convert(parsed!)
        #expect(result.event == nil)
        #expect(result.write == "\u{1B}[?1016l\u{1B}[?1006h\u{1B}[?1016$p")
        _ = negotiation.hear(bytes("\u{1B}[?1016;2$y"))
        #expect(negotiation.phase == .unavailable)
        #expect(negotiation.frame(wanted: true, grid: (56, 19), host: ghostty).isEmpty)
    }

    @Test("A drag past the window is held to the last cell, as cell reports are, not distrusted")
    func dragOffGrid() {
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(ghostty, grid: (56, 19), cell: (16, 34))
        let event = negotiation.read(5000, 5000, code: 32)
        #expect(event?.x == 55)
        #expect(event?.y == 18)
        #expect(negotiation.phase == .on)
    }

    @Test("A report left of or above the window is held to zero, not lost")
    func negativeReport() {
        let event = MouseEvent.parseSGR(bytes("\u{1B}[<0;-5;-12m"))
        #expect(event?.x == 0)
        #expect(event?.y == 0)
        #expect(event?.phase == .released)
    }

    // MARK: The cell size

    @Test("A host nobody has measured needs its two answers to agree")
    func agreement() {
        let unmeasured = PixelMouseNegotiation.Host(cellSource: .agreement)
        var agreeing = PixelMouseNegotiation()
        agreeing.negotiate(unmeasured, grid: (80, 24), cell: (10, 20), area: (800, 480))
        #expect(agreeing.readsPixels)
        #expect(agreeing.cellSize == .init(width: 10, height: 20))

        var windowSized = PixelMouseNegotiation()
        windowSized.negotiate(unmeasured, grid: (80, 25), cell: (7, 17), area: (570, 458))
        #expect(windowSized.phase == .unavailable, "iTerm2's answers: they would be a different unit, for all anyone knows")

        var halved = PixelMouseNegotiation()
        halved.negotiate(unmeasured, grid: (80, 24), cell: (10, 20), area: (1600, 960))
        #expect(halved.phase == .unavailable)
    }

    @Test("xterm.js's fractional cell comes from the area, checked against the rounded answer")
    func xtermJS() {
        let host = PixelMouseNegotiation.Host(countsFromZero: true, cellSource: .areaOverGrid)
        var negotiation = PixelMouseNegotiation()
        negotiation.negotiate(host, grid: (100, 40), cell: (8, 17), area: (782, 680))
        #expect(negotiation.cellSize == .init(width: 7.82, height: 17))
        #expect(negotiation.read(781, 0)?.x == 99, "the last column, where a rounded 8 would say 97")
    }
}

/// The negotiation through a real `Terminal`: what goes down the wire, in what
/// order, and what comes out of `readEvent`.
@MainActor
@Suite("The pixel mouse on the wire")
struct PixelMouseWireTests {
    private final class Wire {
        var reads: [[UInt8]] = []
        var writes: [String] = []
        var written: String { writes.joined() }
    }

    private func makeTerminal() -> (Terminal, Wire) {
        let terminal = Terminal()
        let wire = Wire()
        terminal.readSource = { buffer in
            guard !wire.reads.isEmpty else { return 0 }
            let chunk = wire.reads.removeFirst()
            for (index, byte) in chunk.enumerated() { buffer[index] = byte }
            return chunk.count
        }
        terminal.exchangeTransport = .init(send: { wire.writes.append($0) }, waitForInput: { _ in true })
        terminal.reportedWindowSize = (56, 19)
        return (terminal, wire)
    }

    /// Everything `readEvent` makes of `text`.
    private func events(_ text: String, _ terminal: Terminal, _ wire: Wire) -> [MouseEvent] {
        wire.reads.append(bytes(text))
        var mice: [MouseEvent] = []
        while let input = terminal.readEvent() {
            if case .mouse(let event) = input { mice.append(event) }
        }
        return mice
    }

    private let picks = MouseSupport(clicks: true, scrolling: true, drag: true, subCellLocations: true)

    /// Asked of Ghostty as `Host.of` would have found it, and answered.
    private func negotiated() -> (Terminal, Wire) {
        let (terminal, wire) = makeTerminal()
        _ = terminal.pixelMouse.update(wanted: true, grid: (56, 19), cellReading: nil, host: ghostty)
        _ = events("\u{1B}[6;34;16t\u{1B}[4;646;896t\u{1B}[?1016;2$y", terminal, wire)
        _ = events("\u{1B}[?1016;1$y", terminal, wire)
        wire.writes.removeAll()
        return (terminal, wire)
    }

    @Test("Reports before the fence's reply are cells, those after it pixels, with the same bytes")
    func reportsEitherSideOfTheFence() {
        let (terminal, wire) = makeTerminal()
        _ = terminal.pixelMouse.update(wanted: true, grid: (56, 19), cellReading: nil, host: ghostty)
        let before = events("\u{1B}[6;34;16t\u{1B}[4;646;896t\u{1B}[?1016;2$y\u{1B}[<0;33;9M", terminal, wire)
        #expect(wire.written == "\u{1B}[?1016h\u{1B}[?1016$p")
        #expect(before.map(\.x) == [32], "in the pipe when the mode changed, so in cells")
        let after = events("\u{1B}[?1016;1$y\u{1B}[<0;33;69M", terminal, wire)
        #expect(after.map(\.x) == [2])
        #expect(after.map(\.y) == [2])
        #expect(after.first?.subcellX == 1.0 / 16)
    }

    @Test("A tracking change sends `?1016h` after the `?1006h` that would drop it")
    func trackingChangeKeepsPixels() {
        let (terminal, wire) = negotiated()
        terminal.applyMouseSupport(picks)
        wire.writes.removeAll()
        var more = picks
        more.motion = true
        terminal.applyMouseSupport(more)
        #expect(wire.written.hasSuffix("\u{1B}[?1003h\u{1B}[?1006h\u{1B}[?1016h"))
    }

    @Test("A terminal that never answers is never set, and its reports are cells")
    func silentTerminal() {
        let (terminal, wire) = makeTerminal()
        _ = terminal.pixelMouse.update(wanted: true, grid: (56, 19), cellReading: nil, host: ghostty)
        #expect(events("\u{1B}[<0;33;9M", terminal, wire).map(\.x) == [32])
        #expect(!wire.written.contains("1016h"))
    }

    @Test("Nothing that doesn't ask ever writes a thing about the mode")
    func appThatDoesNotAsk() {
        let (terminal, wire) = makeTerminal()
        terminal.applyMouseSupport(.full)
        terminal.applyMouseSupport(.standard)
        terminal.applyMouseSupport(.disabled)
        #expect(!wire.written.contains("1016"))
        #expect(!wire.written.contains("$p"))
    }

    @Test("Going quiet asks no question for a shell to read, and teardown resets the mode")
    func quiet() {
        let (terminal, wire) = negotiated()
        terminal.applyMouseSupport(picks)
        wire.writes.removeAll()
        terminal.applyMouseSupport(.disabled)
        #expect(wire.written.contains("\u{1B}[?1016l"))
        #expect(!wire.written.contains("$p"))
        #expect(Terminal.inputModesOff.contains("\u{1B}[?1016l\u{1B}[?1006l"), "in the order that leaves neither")
    }
}
