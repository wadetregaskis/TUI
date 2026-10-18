//  🖥️ TUIkit — Terminal UI Kit for Swift
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
import TUIkitCore
import TUIkitView

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
        let buffer = TUIkitView.renderToBuffer(content, context: context)
        let (columns, rows) = (buffer.width, buffer.height)
        guard columns > 0, rows > 0 else { return buffer }
        var drawn: any Shape = shape
        if let resolving = drawn as? any EnvironmentResolvedShape {
            drawn = resolving.resolvedShape(in: context.environment)
        }
        // A rectangle keeps the frame, which `clipped()` has already cut to.
        if let rectangle = drawn as? Rectangle, rectangle.insetAmount == 0 { return buffer }
        let kept = Self.keptCells(
            of: drawn, evenOdd: fillStyle.isEOFilled,
            frame: ShapeFrame(columns: columns, rows: rows, aspect: context.environment.imageCellAspect))
        return Self.clearing(buffer, keeping: kept)
    }

    /// Which cells of each row the shape covers at least half of, as runs of
    /// columns.
    static func keptCells(of shape: any Shape, evenOdd: Bool, frame: ShapeFrame) -> [[Range<Int>]] {
        let coverage = ShapeCoverage(cellsOf: shape, evenOdd: evenOdd, frame: frame)
        return (0..<frame.rows).map { row in
            coverage.runs(row: row) { $0 >= 0.5 }
        }
    }

    /// `buffer` with every cell outside `kept` cleared to nothing.
    static func clearing(_ buffer: FrameBuffer, keeping kept: [[Range<Int>]]) -> FrameBuffer {
        let width = buffer.width
        var lines: [String] = []
        lines.reserveCapacity(buffer.height)
        var cleared: [OpacityRegion] = []
        var regions = buffer.opacityRegions
        var runs: [AnimatedCellRun] = []
        for (row, line) in buffer.lines.enumerated() {
            let keep = row < kept.count ? kept[row] : []
            if keep == [0..<width] {
                lines.append(line)
                runs += buffer.animatedCells.filter { $0.offsetY == row }
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
                    runs += buffer.animatedCells.filter { $0.offsetY == row }.compactMap { $0.clipped(toColumns: span) }
                }
            }
            lines.append(rebuilt + ANSIRenderer.reset)
        }
        var result = buffer.replacingLines(lines, width: width, uniformWidth: true)
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
