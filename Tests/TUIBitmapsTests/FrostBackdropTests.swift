//  🖥️ TUI — A Terminal UI framework for Swift
//  FrostBackdropTests.swift
//
//  A material over pictures the terminal draws frosts one picture of
//  everything behind it — the pictures and the cells between them — blurred
//  as one, so the frost runs across a picture's edge instead of stopping at
//  it in a hard rectangle (`Terminal graphics protocols.md` §14.6).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Frost backdrops")
struct FrostBackdropTests {
    private func signature(_ label: String) -> TerminalImageSignature {
        TerminalImageSignature(
            source: .file(label), rawWidth: 8, rawHeight: 8, pixelWidth: 8, pixelHeight: 8,
            colorMode: .trueColor, toneCurve: nil, edgeContrast: 0, dithering: .none,
            monoInk: RGBA(r: 255, g: 255, b: 255), monoPaper: RGBA(r: 0, g: 0, b: 0),
            terminalColors: .unknown)
    }

    /// A page of two 3 × 2 pictures with a one-cell gutter between them.
    private func page(_ store: TerminalImageStore) -> FrameBuffer {
        func picture(_ label: String, _ byte: UInt8) -> [String] {
            store.placeholderRows(
                token: label, signature: signature(label), columns: 3, rows: 2,
                pixels: { ([UInt8](repeating: byte, count: 8 * 8 * 4), .rgba, 8, 8) }) ?? []
        }
        let left = picture("left", 0x20)
        let right = picture("right", 0xE0)
        _ = store.takePending()
        return FrameBuffer(lines: zip(left, right).map { $0 + " " + $1 })
    }

    /// The image cells of `line`, read back.
    private func pictureCells(_ line: String) -> [KittyGraphics.PlaceholderCell?] {
        FrameBuffer.cells(in: line, through: line.strippedLength, defaultForeground: .white, surface: .black).map { cell in
            guard let cell, let ink = cell.foreground?.rgbComponents else { return nil }
            return KittyGraphics.placeholderCell(cell.character, foreground: ink)
        }
    }

    private func frosted(
        _ base: FrameBuffer, store: TerminalImageStore?, resolution: MaterialFrostResolution = .automatic
    ) -> FrameBuffer {
        let context = makeRenderContext(width: 7, height: 2)
        let glass = renderToBuffer(
            Color.clear.frame(width: 7, height: 2).background(.thinMaterial).materialFrostResolution(resolution),
            context: context)
        // As a floating layer is spent over the finished page, at the root.
        return base.compositedResolvingOpacity(
            with: glass, at: (x: 0, y: 0), palette: context.environment.palette, images: store)
    }

    @Test("Glass over two pictures and the gutter between draws one image across all three")
    func oneImageAcross() throws {
        let store = TerminalImageStore()
        let line = frosted(page(store), store: store).lines[0]
        let cells = pictureCells(line)
        let drawn = try cells.map { try #require($0, "every cell under the glass draws a picture") }
        #expect(Set(drawn.map(\.id)).count == 1, "one image, the gutter included")
        #expect(drawn.map(\.column) == Array(0..<7), "each cell its own column of it")
        #expect(store.takePending().contains("a=t"), "its tinted copy reaches the terminal")
    }

    /// With only a glyph's cell laid, a seam showed around each word where a
    /// placeholder cell met a laid one.
    @Test("Where the terminal lays pictures under text, the whole glass is laid, as one block")
    func wholeGlassLaid() throws {
        let store = TerminalImageStore()
        let base = page(store)
        let rows = KittyGraphics.withPictureUnderTextSupport(true) {
            let context = makeRenderContext(width: 7, height: 2)
            let glass = renderToBuffer(
                Text(verbatim: "ab").frame(width: 7, height: 2).background(.thinMaterial), context: context)
            return base.compositedResolvingOpacity(
                with: glass, at: (x: 0, y: 0), palette: context.environment.palette, images: store
            ).lines.map { PictureUnderTextMarker.extracting($0) }
        }
        for row in rows {
            #expect(pictureCells(row.line).allSatisfy { $0 == nil }, "no cell draws the backdrop itself")
            #expect(row.runs.map(\.column) == [0] && row.runs.map(\.columns) == [7], "every cell marked, glyph or none")
        }
        let blocks = PictureUnderTextLayer.blocks(of: rows.map(\.runs))
        let block = try #require(blocks.values.first)
        #expect(blocks.count == 1 && block.row == 0 && block.rows == 2, "one placement for the glass")
    }

    /// The context's cell is the default 8 × 16 pixels a terminal that reports
    /// none is taken to have.
    @Test("A finer resolution sends the glass's picture at that many pixels a cell", arguments: [
        (MaterialFrostResolution.automatic, "s=14,v=8,"), (.downsampled(by: 2), "s=28,v=16,"), (.native, "s=56,v=32,"),
    ])
    func resolution(resolution: MaterialFrostResolution, size: String) throws {
        let store = TerminalImageStore()
        let line = frosted(page(store), store: store, resolution: resolution).lines[0]
        #expect(pictureCells(line).allSatisfy { $0 != nil }, "the glass still draws one picture")
        let sent = store.takePending()
        #expect(sent.contains(size), "7 x 2 cells at the resolution's pixels: \(sent.prefix(200))")
    }

    @Test("With no picture behind, the frost is the averages, as before")
    func noPicturesNoBackdrop() {
        let store = TerminalImageStore()
        let plain = FrameBuffer(lines: ["abc def", "ghi jkl"])
        let line = frosted(plain, store: store).lines[0]
        #expect(pictureCells(line).allSatisfy { $0 == nil })
        #expect(store.takePending().isEmpty)
    }

    /// A picture's cell spells the image's id as its ink; read as a colour it
    /// darkened every box beside a photograph.
    @Test("A picture's cell lends no colour to a frost's average")
    func placeholdersLendNoColour() {
        let picture = KittyGraphics.PlaceholderCell(id: 7, row: 0, column: 0)
        let cell = FrameBuffer.RowCell(
            character: picture.character, style: SGRState(), foreground: .rgb(0, 0, 7), background: nil)
        #expect(FrameBuffer.effectiveRGB(of: cell, surface: .rgb(200, 200, 200), defaultForeground: .white) == nil)
    }
}
