//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasTestFixture.swift
//
//  What the Canvas suites draw with, and read back with.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

/// A surface of `columns` × `rows` cells, each two units tall, drawn by `draw`.
@MainActor
func canvasSurface(
    columns: Int = 4, rows: Int = 2, grain: CanvasGrain = .quadrants, opaque: CanvasRGBA? = nil, linear: Bool = false,
    draw: (inout GraphicsContext, CGSize) -> Void
) -> GraphicsContext.Surface {
    let context = makeRenderContext(width: columns, height: rows)
    let surface = GraphicsContext.Surface(
        canvasOf: columns, rows, unitsPerRow: 2, grid: grain.cellPixels, grain: grain, backdrop: opaque, isLinear: linear,
        symbols: [], context: context)
    var graphics = GraphicsContext(surface: surface)
    draw(&graphics, CGSize(width: CGFloat(columns), height: CGFloat(rows) * 2))
    return surface
}

/// `surface`'s pixels as letters, row by row: `R`, `B`, `.` for clear, `?` else.
func canvasLetters(_ surface: GraphicsContext.Surface) -> [String] {
    let raster = surface.raster
    return (0..<raster.height).map { y in
        String(
            (0..<raster.width).map { x in
                switch raster[x, y] {
                case CanvasRGBA(red: 255, green: 0, blue: 0, alpha: 255): "R"
                case CanvasRGBA(red: 0, green: 0, blue: 255, alpha: 255): "B"
                case .clear: "."
                default: "?"
                }
            })
    }
}

/// `canvas` drawn as a view, in a frame, as a parent asks for it.
@MainActor
func canvasDrawn(_ canvas: some View, columns: Int = 4, rows: Int = 2, depth: ColorDepth = .truecolor) -> FrameBuffer {
    let context = makeRenderContext(width: columns, height: rows)
    return ColorDepth.withCurrent(depth) { renderToBuffer(canvas, context: context) }
}
