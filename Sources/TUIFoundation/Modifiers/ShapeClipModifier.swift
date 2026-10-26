//  🖥️ TUI — A Terminal UI framework for Swift
//  ShapeClipModifier.swift
//
//  A view's cells kept where a shape covers them: `clipShape(_:style:)`.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIView

/// ``View/clipShape(_:style:)``'s view: its content, already cut to its frame,
/// with every cell the shape covers less than half of cleared.
///
/// A cleared cell is a space stating no colour, claimed at a field of 0 — the
/// claim a shape's own uncovered cells make (`ShapeCells`) — so what is behind
/// the view shows there, and the content's claims and animated runs over it
/// are cut away with it.
struct _ShapeClip<Content: View, S: Shape>: View {
    let content: Content
    let shape: S
    let fillStyle: FillStyle

    var body: Never { fatalError("_ShapeClip renders via Renderable") }
}

extension _ShapeClip: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIView.renderToBuffer(content, context: context)
        let (columns, rows) = (buffer.width, buffer.height)
        guard columns > 0, rows > 0 else { return buffer }
        let drawn = resolvedShape(shape, in: context, columns: columns, rows: rows)
        // A rectangle keeps the frame, which `clipped()` has already cut to.
        if let rectangle = drawn as? Rectangle, rectangle.insetAmount == 0 { return buffer }
        let kept = FrameBuffer.cellsKept(
            by: drawn, columns: columns, rows: rows, aspect: context.environment.imageCellAspect,
            evenOdd: fillStyle.isEOFilled)
        return buffer.clearing(keeping: kept)
    }
}

extension FrameBuffer {
    /// Which cells of each row of a `columns` × `rows` frame `shape` covers at
    /// least half of, as runs of columns: the cells a clip to the shape keeps.
    ///
    /// - Parameters:
    ///   - shape: The shape, laid in the frame as a view's is: its rows
    ///     `aspect` units tall.
    ///   - columns: The frame's width.
    ///   - rows: The frame's height.
    ///   - aspect: How many columns tall a row is
    ///     (``EnvironmentValues/imageCellAspect``).
    ///   - evenOdd: Whether the even-odd rule decides what is inside.
    /// - Returns: One list of runs a row.
    package static func cellsKept(
        by shape: any Shape, columns: Int, rows: Int, aspect: Double, evenOdd: Bool = false
    ) -> [[Range<Int>]] {
        let frame = ShapeFrame(columns: columns, rows: rows, aspect: aspect)
        let coverage = ShapeCoverage(cellsOf: shape, evenOdd: evenOdd, frame: frame)
        return (0..<frame.rows).map { row in
            coverage.runs(row: row) { $0 >= 0.5 }
        }
    }

    /// This buffer with every cell outside `kept` cleared to nothing: a space
    /// stating no colour, claimed at a field of 0, so what is behind shows
    /// there, its claims and animated runs cut away with it.
    ///
    /// - Parameter kept: The runs of columns kept, one list a row; a row past
    ///   its end keeps nothing.
    /// - Returns: The buffer, cleared outside `kept`.
    package func clearing(keeping kept: [[Range<Int>]]) -> FrameBuffer {
        var rebuiltLines: [String] = []
        rebuiltLines.reserveCapacity(height)
        var cleared: [OpacityRegion] = []
        var regions = opacityRegions
        var runs: [AnimatedCellRun] = []
        for (row, line) in lines.enumerated() {
            let keep = row < kept.count ? kept[row] : []
            if keep == [0..<width] {
                rebuiltLines.append(line)
                runs += animatedCells.filter { $0.offsetY == row }
                continue
            }
            // The row cut at every edge of the kept runs: alternately cleared
            // and kept, starting cleared (possibly with nothing).
            var widths: [Int] = []
            var column = 0
            for run in keep {
                widths += [run.lowerBound - column, run.count]
                column = run.upperBound
            }
            widths.append(width - column)
            let pieces = line.padToVisibleWidth(width).ansiAwareSlices(runWidths: widths)
            var rebuilt = ""
            column = 0
            for (index, piece) in pieces.enumerated() {
                let span = column..<(column + widths[index])
                column = span.upperBound
                guard !span.isEmpty else { continue }
                if index.isMultiple(of: 2) {
                    rebuilt += ANSIRenderer.reset + String.spaces(span.count)
                    cleared.appendCoalescing(
                        OpacityRegion.claim(
                            offsetX: span.lowerBound, offsetY: row, width: span.count, height: 1, inkAlpha: .max,
                            fieldAlpha: 0))
                    regions = regions.flatMap { $0.subtracting(columns: span, rows: row..<(row + 1)) }
                } else {
                    rebuilt += piece
                    runs += animatedCells.filter { $0.offsetY == row }.compactMap { $0.clipped(toColumns: span) }
                }
            }
            rebuiltLines.append(rebuilt + ANSIRenderer.reset)
        }
        var result = replacingLines(rebuiltLines, width: width, uniformWidth: true)
        result.opacityRegions = regions + cleared
        result.animatedCells = runs
        return result
    }
}

extension _ShapeClip: Layoutable {
    /// Clipping changes what draws, never the frame.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}
