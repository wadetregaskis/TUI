//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HairlineLayerTests.swift
//
//  The lines `.hairline` separators draw, between the diff writer that finds
//  them in a frame and the terminal that holds them: which hosts draw them,
//  where a placement lands in pixels, what a frame sends, and that an idle
//  frame sends nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

// MARK: - Which hosts

@MainActor
@Suite("Hairlines: which hosts draw them")
struct HairlineHostTests {

    private func supported(
        override: Bool? = nil, environment: [String: String] = [:], graphics: Bool = true,
        program: TerminalClient.Program = .ghostty, pixels: Bool = true
    ) -> Bool {
        TerminalClient.hairlinesSupported(
            override: override, environment: environment, graphics: graphics, program: program,
            reportsCellPixels: pixels)
    }

    @Test("Ghostty draws them, where it places pictures and reports its cell's pixels")
    func ghostty() {
        #expect(supported())
        #expect(!supported(graphics: false))
        #expect(!supported(pixels: false))
    }

    /// iTerm2 3.7.3 drew the line in a unit no query revealed (Q3); kitty and
    /// WezTerm are unmeasured; tmux passes nothing a placement could follow.
    @Test("No other host draws them unasked", arguments: TerminalClient.Program.allCases.filter { $0 != .ghostty })
    func others(program: TerminalClient.Program) {
        #expect(!supported(program: program))
    }

    @Test("TUIKIT_HAIRLINES answers for the terminal, and the override for both")
    func ladder() {
        #expect(supported(environment: ["TUIKIT_HAIRLINES": "1"], graphics: false, program: .iTerm2))
        #expect(!supported(environment: ["TUIKIT_HAIRLINES": "0"]))
        #expect(supported(override: true, environment: ["TUIKIT_HAIRLINES": "0"], program: .unidentified))
        #expect(!supported(override: false))
    }

    @Test("The line goes above the glyphs on Ghostty, below them elsewhere, never at 0")
    func layer() {
        #expect(HairlineLayer.z(for: .ghostty) == 1)
        #expect(HairlineLayer.z(for: .iTerm2) == -1)
        #expect(HairlineLayer.z(for: .unidentified) == -1)
        #expect(HairlineLayer(z: 0).z == -1)
    }
}

// MARK: - The layer

@MainActor
@Suite("Hairlines: the layer")
struct HairlineLayerTests {

    /// A Retina Ghostty's cell: 16 × 34 px, so a 2 px line.
    private let geometry = HairlineLayer.Geometry(cellWidth: 16, cellHeight: 34, columns: 40)

    private func run(_ column: Int, _ width: Int, ink: UInt8 = 150) -> HairlineMarker.Run {
        HairlineMarker.Run(column: column, width: width, red: ink, green: ink, blue: ink)
    }

    /// One frame through the layer: what goes before the hold, and what in it.
    private func frame(
        _ layer: HairlineLayer, _ rows: [[HairlineMarker.Run]], geometry: HairlineLayer.Geometry? = nil
    ) -> (before: String, hold: String, moves: [(row: Int, column: Int)]) {
        let terminal = MockTerminal()
        let before = layer.prepare(rows: rows, geometry: geometry ?? self.geometry, compressed: false)
        layer.place(on: terminal, startRow: 1)
        return (before, terminal.allOutput, terminal.cursorMoves)
    }

    private var strip: KittyGraphics.ImageID { HairlineLayer.firstStripID }

    @Test("A run is one strip sent and one placement, at its first cell, cropped to its cells in pixels")
    func firstFrame() {
        let layer = HairlineLayer(z: 1)
        let sent = frame(layer, [[], [run(1, 22)]])
        // The strip: the screen's width by the line's thickness, raw RGB.
        #expect(sent.before.hasPrefix("\u{1B}_Ga=t,q=2,f=24,t=d,s=640,v=2,i=\(strip)"))
        #expect(sent.moves.map(\.row) == [2])
        #expect(sent.moves.map(\.column) == [2])
        let placement = HairlineLayer.placementID(row: 1, index: 0)
        #expect(sent.hold.contains("a=p,i=\(strip),p=\(placement),x=0,y=0,w=352,h=2,C=1,z=1,q=2"))
    }

    @Test("An unchanged frame sends nothing at all")
    func idleFrame() {
        let layer = HairlineLayer(z: 1)
        _ = frame(layer, [[], [run(1, 22)]])
        let again = frame(layer, [[], [run(1, 22)]])
        #expect(again.before.isEmpty)
        #expect(again.hold.isEmpty)
    }

    @Test("A run that moves is placed again under its own id, with no delete and no strip")
    func moved() {
        let layer = HairlineLayer(z: 1)
        _ = frame(layer, [[run(1, 22)]])
        let moved = frame(layer, [[run(3, 10)]])
        #expect(moved.before.isEmpty)
        #expect(!moved.hold.contains("a=d"))
        #expect(moved.hold.contains("p=\(HairlineLayer.placementID(row: 0, index: 0)),x=0,y=0,w=160,"))
    }

    @Test("A run that goes is deleted by its id, and a strip left with no line goes with it")
    func gone() {
        let layer = HairlineLayer(z: 1)
        _ = frame(layer, [[run(1, 22)], [run(1, 22)]])
        let one = frame(layer, [[run(1, 22)]])
        #expect(one.hold.contains("a=d,d=i,i=\(strip),p=\(HairlineLayer.placementID(row: 1, index: 0))"))
        #expect(!one.hold.contains("d=I"))
        let none = frame(layer, [])
        #expect(none.hold.contains("a=d,d=I,q=2,i=\(strip)"))
        #expect(layer.isIdle)
    }

    @Test("A run that changes colour leaves its old strip's placement and takes the new strip's")
    func recoloured() {
        let layer = HairlineLayer(z: 1)
        _ = frame(layer, [[run(1, 22)]])
        let recoloured = frame(layer, [[run(1, 22, ink: 9)]])
        #expect(recoloured.before.contains("i=\(strip - 1)"))
        #expect(recoloured.hold.contains("a=d,d=i,i=\(strip),p="))
        #expect(recoloured.hold.contains("a=p,i=\(strip - 1),"))
    }

    @Test("After an invalidation every strip is deleted and sent again, and every run placed again")
    func invalidated() {
        let layer = HairlineLayer(z: 1)
        _ = frame(layer, [[run(1, 22)]])
        layer.invalidate()
        let again = frame(layer, [[run(1, 22)]])
        #expect(again.before.hasPrefix("\u{1B}_Ga=d,d=I,q=2,i=\(strip)\u{1B}\\\u{1B}_Ga=t,"))
        #expect(again.hold.contains("a=p,i=\(strip),"))
    }

    @Test("A new cell size is an invalidation: the strip is the screen's new width")
    func geometryChange() {
        let layer = HairlineLayer(z: 1)
        _ = frame(layer, [[run(1, 22)]])
        let wider = frame(
            layer, [[run(1, 22)]], geometry: HairlineLayer.Geometry(cellWidth: 16, cellHeight: 34, columns: 50))
        #expect(wider.before.contains("d=I"))
        #expect(wider.before.contains("s=800,v=2"))
    }

    @Test("The farewell deletes every strip and leaves the layer idle")
    func farewell() {
        let layer = HairlineLayer(z: -1)
        _ = frame(layer, [[run(1, 22)], [run(1, 4, ink: 3)]])
        let farewell = layer.farewell()
        #expect(farewell.contains("i=\(strip)"))
        #expect(farewell.contains("i=\(strip - 1)"))
        #expect(layer.isIdle)
    }

    @Test("A frame that prepared nothing writes nothing")
    func placeWithoutPrepare() {
        let layer = HairlineLayer(z: 1)
        _ = frame(layer, [[run(1, 22)]])
        let terminal = MockTerminal()
        #expect(!layer.place(on: terminal, startRow: 1))
        #expect(terminal.allOutput.isEmpty)
    }

    @Test("The line is about a point thick")
    func thickness() {
        #expect(HairlineLayer.Geometry(cellWidth: 16, cellHeight: 34, columns: 1).thickness == 2)
        #expect(HairlineLayer.Geometry(cellWidth: 8, cellHeight: 16, columns: 1).thickness == 1)
    }
}

// MARK: - The writer

@MainActor
@Suite("Hairlines: the diff writer")
struct HairlineWriterTests {

    private let marked = HairlineMarker.marking(" abcdefgh ", columns: 1..<9, red: 1, green: 2, blue: 3)

    private func build(_ writer: FrameDiffWriter, _ lines: [String], width: Int = 20) -> [String] {
        writer.buildReusingOutputLines(
            buffer: FrameBuffer(lines: lines), terminalWidth: width, terminalHeight: lines.count, bgCode: "",
            reset: "\u{1B}[0m")
    }

    @Test("Where hairlines are drawn, the writer reports a row's runs and writes it without the mark")
    func extracts() {
        KittyGraphics.withHairlineSupport(true) {
            let writer = FrameDiffWriter(program: .ghostty)
            let built = build(writer, ["plain", marked])
            #expect(!built.contains { $0.contains("7744") })
            #expect(writer.hairlineRows == [[], [HairlineMarker.Run(column: 1, width: 8, red: 1, green: 2, blue: 3)]])
            // A reused row reuses its runs.
            _ = build(writer, ["plain", marked])
            #expect(writer.rowsBuiltInLastBuild == 0)
            #expect(writer.hairlineRows[1].count == 1)
        }
    }

    @Test("A run past the right edge is cut to it")
    func cutToTheScreen() {
        KittyGraphics.withHairlineSupport(true) {
            let writer = FrameDiffWriter(program: .ghostty)
            _ = build(writer, [marked], width: 5)
            #expect(writer.hairlineRows == [[HairlineMarker.Run(column: 1, width: 4, red: 1, green: 2, blue: 3)]])
        }
    }

    @Test("Where none are drawn, the writer reads nothing")
    func noneDrawn() {
        KittyGraphics.withHairlineSupport(false) {
            let writer = FrameDiffWriter(program: .ghostty)
            _ = build(writer, [marked])
            #expect(writer.hairlineRows.isEmpty)
        }
    }

    /// A breathing row's frames are drawn as the row is, mark and all; the
    /// replay splices one into the built row, which must not reach the
    /// terminal with it.
    @Test("A replay's frame is spliced in without the mark")
    func replayStripsTheMark() {
        KittyGraphics.withHairlineSupport(true) {
            let writer = FrameDiffWriter(program: .ghostty)
            let built = build(writer, [" abcdefgh "])[0]
            let frame = marked.ansiAwareCuttingLeadingColumns(1).ansiAwarePrefix(visibleCount: 8)
            #expect(frame.contains("7744"))
            let run = AnimatedCellRun(offsetX: 1, offsetY: 0, width: 8, frames: [frame], frameTicks: 1, clock: .content)
            let patched = writer.patchingAnimatedRun(run, showing: run.frames[0], in: built, fields: run.fields(onPage: ""))
            #expect(!patched.contains("7744"))
        }
    }
}
