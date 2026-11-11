//  🖥️ TUI — A Terminal UI framework for Swift
//  PaintedCellsCompositeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

/// A picture drawn over content only where it paints
/// (`FrameBuffer.composite(paintedCellsOf:at:)`): what is under its unstyled
/// blank cells — around its glyphs and between them — stays, and what rides on
/// its cells is cut to the cells drawn.
@MainActor
@Suite("Compositing only the cells a picture paints")
struct PaintedCellsCompositeTests {
    private let base = FrameBuffer(lines: ["abcdefghij", "klmnopqrst"])

    @Test("The blanks around and between a picture's glyphs show what is beneath")
    func blanksShowBeneath() {
        var buffer = base
        buffer.composite(paintedCellsOf: FrameBuffer(lines: [" XY  Z    "]), at: (x: 0, y: 1))
        #expect(buffer.lines.map(\.stripped) == ["abcdefghij", "kXYnoZqrst"])
    }

    @Test("A blank styled to show is a cell the picture paints")
    func styledBlankPaints() {
        var buffer = base
        buffer.composite(paintedCellsOf: FrameBuffer(lines: ["  \u{1B}[41m  \u{1B}[0m"]), at: (x: 1, y: 0))
        #expect(buffer.lines[0].stripped == "abc  fghij")
    }

    @Test("A picture's fade reaches only the cells it draws")
    func fadeCutToCellsDrawn() {
        var picture = FrameBuffer(lines: ["X   Y"])
        picture.opacityRegions = [OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.5)]
        var buffer = base
        buffer.composite(paintedCellsOf: picture, at: (x: 2, y: 0))
        let fades = buffer.opacityRegions.map { ($0.offsetX, $0.offsetY, $0.width, $0.height) }
        #expect(fades.count == 2)
        #expect(fades.contains { $0 == (2, 0, 1, 1) } && fades.contains { $0 == (6, 0, 1, 1) }, "\(fades)")
    }

    @Test("A picture that paints nothing changes nothing, and its floating layers still land")
    func blankPictureLiftsLayers() {
        var picture = FrameBuffer(lines: ["          "])
        picture.overlays = [OverlayLayer(offsetX: 1, offsetY: 0, content: FrameBuffer(lines: ["Q"]))]
        var buffer = base
        buffer.composite(paintedCellsOf: picture, at: (x: 3, y: 1))
        #expect(buffer.lines == base.lines)
        #expect(buffer.overlays.map { ($0.offsetX, $0.offsetY) }.first.map { $0 == (4, 1) } == true)
    }
}
