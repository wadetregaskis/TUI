//  🖥️ TUI — A Terminal UI framework for Swift
//  PictureUnderTextLayerTests.swift
//
//  The pictures laid under glyphs that stand on a frosted picture, between the
//  diff writer that finds their runs in a frame and the terminal that holds
//  their placements: which hosts draw them, what a frame sends, and that an
//  idle frame sends nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

// MARK: - Which hosts

@MainActor
@Suite("Pictures under text: which hosts draw them")
struct PictureUnderTextHostTests {

    private func supported(
        override: Bool? = nil, environment: [String: String] = [:], graphics: Bool = true,
        program: TerminalClient.Program = .ghostty
    ) -> Bool {
        TerminalClient.picturesUnderTextSupported(
            override: override, environment: environment, graphics: graphics, program: program)
    }

    @Test("Ghostty draws them, where it places pictures")
    func ghostty() {
        #expect(supported())
        #expect(!supported(graphics: false))
    }

    /// iTerm2 3.7.6 refuses the placement; kitty is unmeasured.
    @Test(
        "No other host draws them unasked", arguments: TerminalClient.Program.allCases.filter { $0 != .ghostty })
    func others(program: TerminalClient.Program) {
        #expect(!supported(program: program))
    }

    @Test("TUI_PICTURES_UNDER_TEXT answers for the terminal, and the override for both")
    func ladder() {
        #expect(supported(environment: ["TUI_PICTURES_UNDER_TEXT": "1"], graphics: false, program: .iTerm2))
        #expect(!supported(environment: ["TUI_PICTURES_UNDER_TEXT": "0"]))
        #expect(supported(override: true, environment: ["TUI_PICTURES_UNDER_TEXT": "0"], program: .unidentified))
        #expect(!supported(override: false))
    }
}

// MARK: - The layer

@MainActor
@Suite("Pictures under text: the layer")
struct PictureUnderTextLayerTests {

    private func run(_ column: Int, _ columns: Int, image: UInt32 = 42, x: Int = 0) -> PictureUnderTextMarker.Run {
        PictureUnderTextMarker.Run(column: column, columns: columns, image: image, x: x, y: 4, width: columns * 2, height: 4)
    }

    /// One frame through the layer: what it wrote in the hold, and where it
    /// moved the cursor.
    private func frame(
        _ layer: PictureUnderTextLayer, _ rows: [[PictureUnderTextMarker.Run]]
    ) -> (hold: String, moves: [(row: Int, column: Int)]) {
        let terminal = MockTerminal()
        layer.prepare(rows: rows)
        layer.place(on: terminal, startRow: 1)
        return (terminal.allOutput, terminal.cursorMoves)
    }

    @Test("A run is one placement at its first cell, cropped to its pixels and scaled to its cells, under the text")
    func firstFrame() {
        let layer = PictureUnderTextLayer()
        let sent = frame(layer, [[], [run(3, 5, x: 6)]])
        #expect(sent.moves.map(\.row) == [2])
        #expect(sent.moves.map(\.column) == [4])
        let placement = PictureUnderTextLayer.placementID(row: 1, index: 0)
        #expect(sent.hold.contains("a=p,i=42,p=\(placement),x=6,y=4,w=10,h=4,c=5,r=1,C=1,z=-1,q=2"))
    }

    @Test("Runs on rows below one another that carry on the image's pixels are one placement, as tall as they are")
    func blocks() {
        let layer = PictureUnderTextLayer()
        let column = (0..<3).map { [PictureUnderTextMarker.Run(column: 2, columns: 5, image: 42, x: 0, y: $0 * 4, width: 10, height: 4)] }
        let sent = frame(layer, [[]] + column)
        #expect(sent.moves.map(\.row) == [2])
        let placement = PictureUnderTextLayer.placementID(row: 1, index: 0)
        #expect(sent.hold.contains("a=p,i=42,p=\(placement),x=0,y=0,w=10,h=12,c=5,r=3,C=1,z=-1,q=2"))
        // A run that does not carry on — other pixels across — starts a block of its own.
        let broken = PictureUnderTextLayer.blocks(of: [
            [run(0, 4)], [PictureUnderTextMarker.Run(column: 0, columns: 4, image: 42, x: 2, y: 8, width: 8, height: 4)],
        ])
        #expect(broken.count == 2)
    }

    @Test("An unchanged frame sends nothing")
    func idleFrame() {
        let layer = PictureUnderTextLayer()
        _ = frame(layer, [[run(0, 4)]])
        #expect(frame(layer, [[run(0, 4)]]).hold.isEmpty)
    }

    @Test("A run that moves on its image is placed again under its own id, with no delete")
    func moved() {
        let layer = PictureUnderTextLayer()
        _ = frame(layer, [[run(0, 4)]])
        let moved = frame(layer, [[run(2, 4, x: 4)]])
        #expect(!moved.hold.contains("a=d"))
        #expect(moved.hold.contains("p=\(PictureUnderTextLayer.placementID(row: 0, index: 0)),x=4,"))
    }

    @Test("A run that goes, or turns to another image, deletes the old placement")
    func goneOrSwapped() {
        let layer = PictureUnderTextLayer()
        _ = frame(layer, [[run(0, 4)], [run(0, 4)]])
        let swapped = frame(layer, [[run(0, 4, image: 43)], [run(0, 4)]])
        #expect(swapped.hold.contains("a=d,d=i,i=42,p=\(PictureUnderTextLayer.placementID(row: 0, index: 0))"))
        #expect(swapped.hold.contains("a=p,i=43,"))
        let gone = frame(layer, [])
        #expect(gone.hold.contains("a=d,d=i,i=43,"))
        #expect(gone.hold.contains("a=d,d=i,i=42,p=\(PictureUnderTextLayer.placementID(row: 1, index: 0))"))
        #expect(layer.isIdle)
    }

    @Test("After an invalidation every placement is deleted and every run placed again")
    func invalidated() {
        let layer = PictureUnderTextLayer()
        _ = frame(layer, [[run(0, 4)]])
        layer.invalidate()
        let again = frame(layer, [[run(0, 4)]])
        #expect(again.hold.contains("a=d,d=i,i=42,"))
        #expect(again.hold.contains("a=p,i=42,"))
    }

    @Test("The farewell deletes every placement and leaves the layer idle")
    func farewell() {
        let layer = PictureUnderTextLayer()
        _ = frame(layer, [[run(0, 4)], [], [run(1, 2, image: 9)]])
        let farewell = layer.farewell()
        #expect(farewell.contains("i=42,") && farewell.contains("i=9,"))
        #expect(layer.isIdle)
    }
}

// MARK: - The writer

@MainActor
@Suite("Pictures under text: the writer")
struct PictureUnderTextWriterTests {

    private let marked = " "
        + (0..<4).map { PictureUnderTextMarker.sequence(.init(image: 42, x: $0 * 2, y: 0, width: 2, height: 4)) + "x" }
        .joined() + "\u{1B}[0m "

    private func build(_ writer: FrameDiffWriter, _ lines: [String], width: Int = 20) -> [String] {
        writer.buildReusingOutputLines(
            buffer: FrameBuffer(lines: lines), terminalWidth: width, terminalHeight: lines.count, bgCode: "",
            reset: "\u{1B}[0m")
    }

    @Test("Where pictures under text are drawn, the writer reports a row's runs and writes it without the mark")
    func extracts() {
        KittyGraphics.withPictureUnderTextSupport(true) {
            let writer = FrameDiffWriter(program: .ghostty)
            let built = build(writer, ["plain", marked])
            #expect(!built.contains { $0.contains("7745") })
            #expect(
                writer.pictureUnderTextRows
                    == [[], [.init(column: 1, columns: 4, image: 42, x: 0, y: 0, width: 8, height: 4)]])
            _ = build(writer, ["plain", marked])
            #expect(writer.rowsBuiltInLastBuild == 0)
            #expect(writer.pictureUnderTextRows[1].count == 1, "a reused row reuses its runs")
        }
    }

    @Test("A run past the right edge is cut to it, its pixels in proportion")
    func cutToTheScreen() {
        KittyGraphics.withPictureUnderTextSupport(true) {
            let writer = FrameDiffWriter(program: .ghostty)
            _ = build(writer, [marked], width: 3)
            #expect(writer.pictureUnderTextRows == [[.init(column: 1, columns: 2, image: 42, x: 0, y: 0, width: 4, height: 4)]])
        }
    }

    @Test("Where none are drawn, the writer reads nothing")
    func noneDrawn() {
        KittyGraphics.withPictureUnderTextSupport(false) {
            let writer = FrameDiffWriter(program: .ghostty)
            _ = build(writer, [marked])
            #expect(writer.pictureUnderTextRows.isEmpty)
        }
    }
}
