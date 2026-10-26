//  🖥️ TUI — A Terminal UI framework for Swift
//  OverflowCoverReachTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

/// Overflow is cut away under the cells a later view paints, and only that
/// view's lines the overflow reaches are read for them
/// (`FrameBuffer.overflowCovered(under:at:)`). The cut must be the one that
/// reading every line gave, layer for layer: these compare the two over
/// shapes made to meet every edge of the rule — overflow above, below,
/// across and beside the later view, ragged and styled lines, blank lines
/// that paint nothing, layers with no cells, and floating layers that are
/// not overflow.
@MainActor
@Suite("Overflow cut under the lines it reaches")
struct OverflowCoverReachTests {

    /// The cut as it was made before the reach: over every painted block of
    /// `later`, each overflow layer cut by each in turn.
    private func coveredReadingEveryLine(
        _ layers: [OverlayLayer], under later: FrameBuffer, at position: (x: Int, y: Int)
    ) -> [OverlayLayer] {
        var covered = layers
        for block in later.paintedBlocks() {
            covered = covered.flatMap { layer -> [OverlayLayer] in
                guard layer.isOverflow else { return [layer] }
                return layer.excluding(
                    x: position.x + block.columns.lowerBound, y: position.y + block.rows.lowerBound,
                    width: block.columns.count, height: block.rows.count)
            }
        }
        return covered
    }

    /// A layer of `width` × `height` cells of `x`, at (`x`, `y`).
    private func layer(x: Int, y: Int, width: Int, height: Int, overflow: Bool = true) -> OverlayLayer {
        var layer = OverlayLayer(
            offsetX: x, offsetY: y,
            content: FrameBuffer(lines: Array(repeating: String(repeating: "x", count: width), count: height)))
        layer.isOverflow = overflow
        return layer
    }

    /// The later view: a page of lines, some ragged, some blank, one styled
    /// blank that paints, so its blocks are several.
    private let later = FrameBuffer(lines: [
        "abcdef    ", "abcdef    ", "  cd      ", "          ", "\u{1B}[41m    \u{1B}[0m      ",
        "abcdefghij", "abcdefghij", "      ghij", "          ", "a         ",
    ])

    private func expectSameCut(_ layers: [OverlayLayer], at position: (x: Int, y: Int)) {
        var buffer = FrameBuffer(lines: ["0123456789"])
        buffer.overlays = layers
        #expect(
            buffer.overflowCovered(under: later, at: position) == coveredReadingEveryLine(layers, under: later, at: position),
            "layers \(layers.map { ($0.offsetX, $0.offsetY, $0.content.width, $0.content.height) }) at \(position)")
    }

    @Test("One overflow layer, anywhere round the later view: the same cut")
    func oneLayerEverywhere() {
        for y in -4...13 {
            for x in -4...12 {
                for (width, height) in [(1, 1), (3, 2), (12, 1), (2, 12), (14, 14)] {
                    expectSameCut([layer(x: x, y: y, width: width, height: height)], at: (x: 1, y: 2))
                }
            }
        }
    }

    @Test("Several layers, some far apart, some not overflow, some with no cells: the same cut")
    func severalLayers() {
        let shapes: [[OverlayLayer]] = [
            [layer(x: 0, y: 2, width: 4, height: 1), layer(x: 2, y: 10, width: 3, height: 2)],
            [layer(x: 0, y: -3, width: 4, height: 2), layer(x: 0, y: 30, width: 4, height: 2)],
            [layer(x: 0, y: 3, width: 4, height: 3, overflow: false), layer(x: 5, y: 5, width: 2, height: 2)],
            [layer(x: 0, y: 3, width: 0, height: 3)],
            [layer(x: 0, y: 40, width: 3, height: 0), layer(x: 1, y: 4, width: 2, height: 1)],
            [layer(x: -20, y: 4, width: 2, height: 1), layer(x: 30, y: 6, width: 2, height: 3)],
            [layer(x: 0, y: 0, width: 4, height: 1, overflow: false)],
        ]
        for layers in shapes {
            for position in [(x: 0, y: 0), (x: 1, y: 2), (x: -3, y: 5), (x: 4, y: -2)] {
                expectSameCut(layers, at: position)
            }
        }
    }

    @Test("Over a later view of no lines, nothing is cut")
    func emptyLater() {
        var buffer = FrameBuffer(lines: ["0123456789"])
        let layers = [layer(x: 0, y: 1, width: 3, height: 2), layer(x: 0, y: 1, width: 0, height: 2)]
        buffer.overlays = layers
        #expect(buffer.overflowCovered(under: FrameBuffer(), at: (x: 0, y: 1)) == layers)
    }
}
