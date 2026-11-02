//  🖥️ TUI — A Terminal UI framework for Swift
//  ClassicPlacementPictureTests.swift
//
//  A picture on a host that speaks the Kitty graphics protocol and has no
//  Unicode placeholders: the cells become spaces at the writer, and a classic
//  placement of what they covered is kept in step with the terminal.
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
@Suite("Classic placements: which hosts draw by them")
struct ClassicPlacementHostTests {

    private func classic(
        override: Bool? = nil, environment: [String: String] = [:], placement: Bool? = nil, classic: Bool? = nil
    ) -> Bool {
        TerminalClient.classicPlacementsInUse(
            override: override, environment: environment, detectedPlacement: placement, detectedClassic: classic)
    }

    @Test("A host with placeholders keeps them, a host with none takes the classic placement")
    func handshake() {
        #expect(!classic(placement: true, classic: true), "Ghostty, iTerm2")
        #expect(classic(placement: false, classic: true), "Warp, Konsole, WezTerm")
        #expect(!classic(placement: false, classic: false), "tmux, Apple Terminal")
        #expect(!classic(), "never asked")
    }

    @Test("TUI_GRAPHICS=classic asks for them anywhere, and 1 and 0 for no classic placement")
    func environment() {
        #expect(classic(environment: ["TUI_GRAPHICS": "classic"], placement: true, classic: true))
        #expect(classic(environment: ["TUI_GRAPHICS": "classic"]))
        #expect(!classic(environment: ["TUI_GRAPHICS": "1"], placement: false, classic: true))
        #expect(!classic(environment: ["TUI_GRAPHICS": "0"], placement: false, classic: true))
    }

    @Test("Pictures turned off in code are off, and on in code still go by the handshake")
    func override() {
        #expect(!classic(override: false, environment: ["TUI_GRAPHICS": "classic"], placement: false, classic: true))
        #expect(classic(override: true, placement: false, classic: true))
        #expect(!classic(override: true))
    }

    @Test("Either kind of placement is pictures")
    func graphics() {
        #expect(TerminalClient.graphicsSupported(override: nil, environment: [:], detected: true))
        #expect(TerminalClient.graphicsSupported(override: nil, environment: ["TUI_GRAPHICS": "classic"], detected: nil))
    }

    /// Measured: Warp drew the whole picture for every crop it was asked for.
    @Test("Warp is the one host measured to ignore the source rectangle")
    func crops() {
        for program in TerminalClient.Program.allCases {
            #expect(TerminalClient.classicPlacementsCrop(program: program) == (program != .warp))
        }
    }
}

// MARK: - The cells

@Suite("Classic placements: reading a picture's cells")
struct PlaceholderRunTests {

    @Test("Rows of placeholder cells become spaces and a run")
    func rowsBecomeSpaces() {
        let rows = KittyGraphics.placeholderRows(id: 42, columns: 3, rows: 2)
        let (line, runs) = KittyGraphics.extractingPlaceholders(rows[1])
        #expect(!line.unicodeScalars.contains(.terminalImagePlaceholder))
        #expect(line.strippedLength == 3)
        #expect(runs == [.init(column: 0, columns: 3, image: 42, imageRow: 1, imageColumn: 0)])
    }

    @Test("A placement's cells say which placement they name")
    func scaledCells() {
        let rows = KittyGraphics.placeholderRows(id: 42, columns: 2, rows: 1, placement: 2)
        #expect(
            KittyGraphics.extractingPlaceholders(rows[0]).runs
                == [.init(column: 0, columns: 2, image: 42, placement: 2, imageRow: 0, imageColumn: 0)])
    }

    @Test("Cells around text are counted in columns, a wide glyph's two")
    func columnsCount() {
        let cell = KittyGraphics.PlaceholderCell(id: 7, row: 2, column: 5).spelled
        let (line, runs) = KittyGraphics.extractingPlaceholders("ab🙂" + cell + "\u{1B}[39mz")
        #expect(runs == [.init(column: 4, columns: 1, image: 7, imageRow: 2, imageColumn: 5)])
        #expect(line.strippedLength == 6)
    }

    /// A modal over a picture's middle.
    @Test("A cut in the cells is a cut in the runs, and the image's columns carry on past it")
    func covered() {
        func cell(_ column: Int) -> String { KittyGraphics.PlaceholderCell(id: 7, row: 0, column: column).spelled }
        let line = cell(0) + cell(1) + "\u{1B}[39mXX" + cell(4) + cell(5) + "\u{1B}[39m"
        #expect(
            KittyGraphics.extractingPlaceholders(line).runs == [
                .init(column: 0, columns: 2, image: 7, imageRow: 0, imageColumn: 0),
                .init(column: 4, columns: 2, image: 7, imageRow: 0, imageColumn: 4),
            ])
    }

    @Test("Two images side by side are two runs")
    func twoImages() {
        let line = KittyGraphics.placeholderRows(id: 1, columns: 2, rows: 1)[0]
            + KittyGraphics.placeholderRows(id: 2, columns: 2, rows: 1)[0]
        #expect(KittyGraphics.extractingPlaceholders(line).runs.map(\.image) == [1, 2])
    }

    @Test("A cell whose ink names no image still goes, and makes no run")
    func noName() {
        let cell = KittyGraphics.PlaceholderCell(id: 7, row: 0, column: 0).character
        let (line, runs) = KittyGraphics.extractingPlaceholders(String(cell))
        #expect(line == " ")
        #expect(runs.isEmpty)
    }

    @Test("A line with no picture comes back as it went")
    func untouched() {
        let line = "\u{1B}[38;2;1;2;3mhello\u{1B}[0m"
        #expect(KittyGraphics.extractingPlaceholders(line).line == line)
    }
}

// MARK: - The writer

@MainActor
@Suite("Classic placements: the writer")
struct ClassicPlacementWriterTests {

    private func build(_ writer: FrameDiffWriter, _ lines: [String], width: Int = 20) -> [String] {
        writer.buildReusingOutputLines(
            buffer: FrameBuffer(lines: lines), terminalWidth: width, terminalHeight: lines.count, bgCode: "",
            reset: "\u{1B}[0m")
    }

    private var rows: [String] { KittyGraphics.placeholderRows(id: 42, columns: 4, rows: 2) }

    @Test("No placeholder reaches the host, and the runs are read off the frame")
    func substituted() {
        KittyGraphics.withClassicPlacements(true) {
            let writer = FrameDiffWriter(program: .warp)
            let built = build(writer, rows)
            #expect(!built.contains { $0.unicodeScalars.contains(.terminalImagePlaceholder) })
            #expect(
                writer.imagePlaceholderRows == [
                    [.init(column: 0, columns: 4, image: 42, imageRow: 0, imageColumn: 0)],
                    [.init(column: 0, columns: 4, image: 42, imageRow: 1, imageColumn: 0)],
                ])
            _ = build(writer, rows)
            #expect(writer.rowsBuiltInLastBuild == 0)
            #expect(writer.imagePlaceholderRows.count == 2, "a reused row reuses its runs")
        }
    }

    @Test("A run past the right edge is cut to it")
    func cutToTheScreen() {
        KittyGraphics.withClassicPlacements(true) {
            let writer = FrameDiffWriter(program: .warp)
            _ = build(writer, rows, width: 3)
            #expect(writer.imagePlaceholderRows[0] == [.init(column: 0, columns: 3, image: 42, imageRow: 0, imageColumn: 0)])
        }
    }

    @Test("A host with placeholders keeps its cells")
    func placeholders() {
        KittyGraphics.withClassicPlacements(false) {
            let writer = FrameDiffWriter(program: .ghostty)
            let built = build(writer, rows)
            #expect(built.allSatisfy { $0.unicodeScalars.contains(.terminalImagePlaceholder) })
            #expect(writer.imagePlaceholderRows.isEmpty)
        }
    }
}

// MARK: - The store

@Suite("Classic placements: what a run's cells cover")
struct ClassicPlacementStoreTests {

    private struct Signature: ImageStoreSignature {
        var name: String
        var storeBucket: String { name }
    }

    /// A store holding one 400 x 200 px picture in a box of 40 x 20 cells.
    private func store(pixels: (width: Int, height: Int) = (400, 200)) -> (TerminalImageStore, KittyGraphics.ImageID) {
        let store = TerminalImageStore()
        let rows = store.placeholderRows(token: "t", signature: Signature(name: "a"), columns: 40, rows: 20) {
            (
                [UInt8](repeating: 0, count: pixels.width * pixels.height * 3), .rgb, pixels.width, pixels.height
            )
        }
        let id = KittyGraphics.extractingPlaceholders(rows?[0] ?? "").runs.first?.image ?? 0
        return (store, id)
    }

    @Test("A run's pixels are its cells' share of the picture's")
    func proportional() {
        let (store, id) = store()
        let run = store.placementRun(
            for: .init(column: 3, columns: 10, image: id, imageRow: 2, imageColumn: 5))
        #expect(run == .init(column: 3, columns: 10, image: id, x: 50, y: 20, width: 100, height: 10))
    }

    /// The picture a block makes of them is whole only if nothing was rounded off.
    @Test("Every row of a picture with cells of no whole number of pixels still tiles")
    func tiles() {
        let (store, id) = store(pixels: (333, 77))
        var y = 0
        for row in 0..<20 {
            let run = store.placementRun(for: .init(column: 0, columns: 40, image: id, imageRow: row, imageColumn: 0))
            #expect(run?.y == y)
            #expect(run?.width == 333)
            y += run?.height ?? 0
        }
        #expect(y == 77)
    }

    @Test("A picture smaller than its cells still gives every cell a pixel")
    func tiny() {
        let (store, id) = store(pixels: (4, 2))
        let run = store.placementRun(for: .init(column: 0, columns: 1, image: id, imageRow: 19, imageColumn: 39))
        #expect(run == .init(column: 0, columns: 1, image: id, x: 3, y: 1, width: 1, height: 1))
    }

    @Test("A scaled placement's cells count across its own box")
    func scaled() {
        let (store, id) = store()
        _ = store.scaledPlaceholderRows(of: id, columns: 10, rows: 5)
        let run = store.placementRun(
            for: .init(column: 0, columns: 5, image: id, placement: 2, imageRow: 1, imageColumn: 5))
        #expect(run == .init(column: 0, columns: 5, image: id, x: 200, y: 40, width: 200, height: 40))
    }

    @Test("A copy's cells count across what the copy was sent at")
    func copy() throws {
        let (store, id) = store()
        let transform = ImageTransform(blurs: true, toward: (0, 0, 0), fraction: 0.5)
        let copy = try #require(
            store.derived(KittyGraphics.PlaceholderCell(id: id, row: 0, column: 0), by: transform))
        let run = store.placementRun(for: .init(column: 0, columns: 40, image: copy.id, imageRow: 0, imageColumn: 0))
        #expect(run == .init(column: 0, columns: 40, image: copy.id, x: 0, y: 0, width: 80, height: 4))
    }

    @Test("An image the store does not hold, or a cell outside it, is no run")
    func unknown() {
        let (store, id) = store()
        #expect(store.placementRun(for: .init(column: 0, columns: 1, image: id + 99, imageRow: 0, imageColumn: 0)) == nil)
        #expect(store.placementRun(for: .init(column: 0, columns: 1, image: id, imageRow: 20, imageColumn: 0)) == nil)
    }

    @Test("Only all of a picture's pixels are the whole picture")
    func whole() {
        let (store, id) = store()
        #expect(store.isWholePicture(.init(column: 9, columns: 40, image: id, x: 0, y: 0, width: 400, height: 200)))
        #expect(!store.isWholePicture(.init(column: 9, columns: 20, image: id, x: 0, y: 0, width: 200, height: 200)))
        #expect(!store.isWholePicture(.init(column: 9, columns: 40, image: id + 99, x: 0, y: 0, width: 400, height: 200)))
    }

    @Test("A host told to draw by classic placements is sent no virtual one")
    func noVirtualPlacement() {
        KittyGraphics.withClassicPlacements(true) {
            #expect(KittyGraphics.placement(id: 1, columns: 2, rows: 2).isEmpty)
        }
        KittyGraphics.withClassicPlacements(false) {
            #expect(!KittyGraphics.placement(id: 1, columns: 2, rows: 2).isEmpty)
        }
    }
}

// MARK: - The layer

@MainActor
@Suite("Classic placements: the layer")
struct ClassicPlacementLayerTests {

    private func run(_ y: Int, height: Int = 4) -> PictureUnderTextMarker.Run {
        .init(column: 2, columns: 10, image: 9, x: 0, y: y, width: 40, height: height)
    }

    private func placed(_ layer: PicturePlacementLayer, rewritten: [Int] = []) -> String {
        let terminal = MockTerminal()
        layer.place(on: terminal, startRow: 1, rewritten: rewritten)
        return terminal.allOutput
    }

    @Test("A block is one placement, above the cells, of the pixels its rows make")
    func oneBlock() {
        let layer = PicturePlacementLayer(z: PicturePlacementLayer.overCells)
        layer.prepare(rows: [[run(0)], [run(4)], [run(8)]])
        let out = placed(layer)
        #expect(out.contains("a=p,i=9,p=1,x=0,y=0,w=40,h=12,c=10,r=3,C=1,z=1,q=2"))
    }

    @Test("A row the frame wrote costs the placement across it another send, and none else")
    func rewrittenRow() {
        let layer = PicturePlacementLayer(z: PicturePlacementLayer.overCells)
        layer.prepare(rows: [[run(0)], [run(4)], [], [run(100)]])
        _ = placed(layer)
        layer.prepare(rows: [[run(0)], [run(4)], [], [run(100)]])
        #expect(placed(layer).isEmpty, "nothing changed and nothing was written")
        layer.prepare(rows: [[run(0)], [run(4)], [], [run(100)]])
        #expect(placed(layer, rewritten: [2]).isEmpty, "a row no block crosses")
        layer.prepare(rows: [[run(0)], [run(4)], [], [run(100)]])
        let again = placed(layer, rewritten: [1])
        #expect(again.contains("p=1,"))
        #expect(!again.contains("p=769"), "the block on row 3 is untouched")
    }

    @Test("A block the host cannot be shown is not placed, and goes if it was")
    func keeping() {
        let layer = PicturePlacementLayer(z: PicturePlacementLayer.overCells)
        layer.prepare(rows: [[run(0, height: 200)]]) { $0.height == 200 ? $0 : nil }
        #expect(placed(layer).contains("a=p"))
        layer.prepare(rows: [[run(0, height: 100)]]) { $0.height == 200 ? $0 : nil }
        let out = placed(layer)
        #expect(!out.contains("a=p"))
        #expect(out.contains("a=d,d=i,i=9,p=1"))
    }
}
