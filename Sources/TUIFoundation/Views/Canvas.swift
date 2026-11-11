//  🖥️ TUI — A Terminal UI framework for Swift
//  Canvas.swift
//
//  SwiftUI's `Canvas`: immediate-mode drawing through a `GraphicsContext`, at
//  the finest grain the terminal offers.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIStyling
import TUIView

/// A view that draws through a closure — mirrors SwiftUI's `Canvas`.
///
/// ```swift
/// Canvas { context, size in
///     let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
///     context.fill(disc, with: .color(.orange))
///     context.draw(Text("Hello"), at: CGPoint(x: size.width / 2, y: size.height / 2))
/// }
/// .frame(width: 24, height: 12)
/// ```
///
/// `size` and every position are in a ``Shape``'s square units: a column across,
/// and about two of them down a row (``EnvironmentValues/imageCellAspect``), so a
/// disc in a 24 × 12-cell frame is round. A canvas fills what it is offered, as a
/// shape does, and clips to its frame.
///
/// Paths and images land on pixels: the terminal's own where it places pictures
/// in its cell grid, otherwise those its glyphs can draw (``CanvasGrain``). Text
/// and symbols are cells; ``GraphicsContext`` says how the two meet. A picture
/// and its colours are the terminal's to blend, so where a canvas leaves pixels
/// clear they show the cell behind them; a cell with no pixels at all is not
/// drawn, and what is behind the canvas shows through it whole.
///
/// The renderer runs on the main actor as the frame is drawn, each time the
/// canvas's parent is. Drive one from a ``TimelineView`` to animate it.
nonisolated public struct Canvas<Symbols: View>: View {
    /// The views the renderer can draw by tag (``GraphicsContext/resolveSymbol(id:)``).
    public var symbols: Symbols

    /// Draws the canvas's content.
    public var renderer: (inout GraphicsContext, CGSize) -> Void

    /// Whether the canvas is fully opaque. Its pixels start as the palette's
    /// background rather than clear, so nothing behind shows through.
    public var isOpaque: Bool

    /// The colour space the canvas's drawing mixes in. ``ColorRenderingMode/extendedLinear``
    /// is ``ColorRenderingMode/linear``: a pixel here holds the standard range.
    public var colorMode: ColorRenderingMode

    /// Asks SwiftUI to render off the main thread. Kept for its signature: a
    /// terminal frame is assembled from cells on the main actor, so the renderer
    /// runs there whatever this says, as SwiftUI allows.
    public var rendersAsynchronously: Bool

    /// Creates a canvas that can draw `symbols`.
    ///
    /// - Parameters:
    ///   - opaque: Whether the canvas is fully opaque.
    ///   - colorMode: The colour space its drawing mixes in.
    ///   - rendersAsynchronously: Kept for SwiftUI's signature; see the property.
    ///   - renderer: Draws the canvas's content into the context, of the size.
    ///   - symbols: The views the renderer can draw, each with a `.tag(_:)`.
    public init(
        opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
        renderer: @escaping (inout GraphicsContext, CGSize) -> Void, @ViewBuilder symbols: () -> Symbols
    ) {
        self.symbols = symbols()
        self.renderer = renderer
        self.isOpaque = opaque
        self.colorMode = colorMode
        self.rendersAsynchronously = rendersAsynchronously
    }

    /// The canvas's content, drawn by the terminal-specific core.
    @MainActor public var body: some View {
        _CanvasCore(symbols: symbols, renderer: renderer, isOpaque: isOpaque, colorMode: colorMode)
    }
}

extension Canvas where Symbols == EmptyView {
    /// Creates a canvas.
    ///
    /// - Parameters:
    ///   - opaque: Whether the canvas is fully opaque.
    ///   - colorMode: The colour space its drawing mixes in.
    ///   - rendersAsynchronously: Kept for SwiftUI's signature; see the property.
    ///   - renderer: Draws the canvas's content into the context, of the size.
    public init(
        opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
        renderer: @escaping (inout GraphicsContext, CGSize) -> Void
    ) {
        self.init(
            opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer,
            symbols: { EmptyView() })
    }
}

// MARK: - The core

/// A signature of a canvas's picture: its pixels, so a frame that draws what
/// the last did sends nothing.
private struct CanvasPictureSignature: ImageStoreSignature {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    var storeBucket: some Hashable { [width, height] }
}

/// Where a ``Canvas`` becomes cells: runs the renderer over a surface at the
/// finest grain on offer, and turns what it drew into a buffer.
private struct _CanvasCore<Symbols: View>: View, Renderable, Layoutable {
    let symbols: Symbols
    let renderer: (inout GraphicsContext, CGSize) -> Void
    let isOpaque: Bool
    let colorMode: ColorRenderingMode

    var body: Never { fatalError("_CanvasCore renders via Renderable") }

    /// As a shape: what it is offered, and SwiftUI's ideal of 10 in each axis
    /// where nothing is said.
    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        Rectangle().sizeThatFits(proposal)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let columns = max(0, context.availableWidth)
        let rows = max(0, context.availableHeight)
        guard columns > 0, rows > 0 else { return FrameBuffer(lines: []) }
        // A measure pass draws nothing: the renderer is the app's, and a pass
        // that may never be seen need not pay for it.
        if context.isMeasuring {
            let blank = String(repeating: " ", count: columns)
            return FrameBuffer(lines: Array(repeating: blank, count: rows), width: columns, lineWidths: Array(repeating: columns, count: rows))
        }
        let grain = context.environment.canvasGrain
        if grain == .automatic, let picture = picture(columns: columns, rows: rows, context: context) { return picture }
        let surface = run(columns: columns, rows: rows, grid: grain.cellPixels, grain: grain, context: context)
        let monochrome = ColorDepth.current == .noColor
        let cells = surface.hasPaint || isOpaque ? surface.pixelCells(monochrome: monochrome) : ShapeCells(width: columns, height: rows)
        return surface.glyphs(over: cells.buffer())
    }

    /// Draws the canvas on a new surface.
    private func run(
        columns: Int, rows: Int, grid: (across: Int, down: Int), grain: CanvasGrain, context: RenderContext
    ) -> GraphicsContext.Surface {
        let aspect = context.environment.imageCellAspect
        // Empty for the canvas that has none, which is most; resolving a member
        // is a walk of the content, not a drawing of it.
        let members =
            Symbols.self == EmptyView.self
            ? []
            : subviewGroups(of: symbols, in: context.withChildIdentity(erasedType: Self.self, key: "symbols"))
                .flatMap(\.members)
        var backdrop: CanvasRGBA?
        if isOpaque, let rgb = context.environment.palette.background.resolve(with: context.environment.palette).rgbComponents {
            backdrop = CanvasRGBA(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 255)
        }
        let surface = GraphicsContext.Surface(
            canvasOf: columns, rows, unitsPerRow: aspect, grid: grid, grain: grain, backdrop: backdrop,
            isLinear: colorMode != .nonLinear, symbols: members, context: context)
        var graphics = GraphicsContext(surface: surface)
        observingBodyClosure(of: Self.self, context: context) {
            renderer(&graphics, CGSize(width: CGFloat(columns), height: CGFloat(rows) * aspect))
        }
        return surface
    }

    // MARK: A picture

    /// The canvas as the terminal's own pixels, or `nil` where it draws cells:
    /// the terminal does not place pictures, the canvas is too big for them, or
    /// the drawing used a colour a pixel cannot hold (the terminal's own, before
    /// it has reported it).
    private func picture(columns: Int, rows: Int, context: RenderContext) -> FrameBuffer? {
        guard columns <= KittyGraphics.maximumCellExtent, rows <= KittyGraphics.maximumCellExtent,
            let graphics = context.gradientGraphics(token: "canvas-\(context.identity.path)")
        else { return nil }
        let grid = Self.pictureGrid(cellPixels: graphics.cellPixels)
        guard columns * grid.across * rows * grid.down <= Self.largestPicture else {
            graphics.store.release(token: graphics.token)
            return nil
        }
        let surface = run(columns: columns, rows: rows, grid: grid, grain: .automatic, context: context)
        guard surface.hasPaint || isOpaque else {
            // Glyphs alone: cells say them just as well, with nothing to send.
            graphics.store.release(token: graphics.token)
            return surface.glyphs(over: ShapeCells(width: columns, height: rows).buffer())
        }
        guard !surface.hasColourWithoutChannels else {
            graphics.store.release(token: graphics.token)
            return nil
        }
        let raster = surface.raster
        let opaque = raster.isOpaque
        let width = raster.width
        let height = raster.height
        let bytes = raster.bytes
        let signature = CanvasPictureSignature(bytes: bytes, width: width, height: height)
        guard
            let lines = graphics.store.placeholderRows(
                token: graphics.token, signature: signature, columns: columns, rows: rows,
                pixels: { (opaque ? Self.opaqueBytes(bytes) : bytes, opaque ? .rgb : .rgba, width, height) })
        else { return nil }
        var buffer = FrameBuffer(lines: lines, width: columns, lineWidths: Array(repeating: columns, count: lines.count))
        if !opaque { buffer = Self.punchingClearCells(buffer, raster: raster, grid: grid, columns: columns, rows: rows) }
        return surface.glyphs(over: buffer)
    }

    /// The most pixels a canvas sends as a picture a frame. Past 4 megapixels,
    /// a 16 MB array for one canvas, it draws in cells.
    private static var largestPicture: Int { 1 << 22 }

    /// A cell's pixels in a picture: the cell's size over the largest common
    /// factor that leaves ``GradientRaster/minimumPixelsPerCell`` each way, as a
    /// ramp's picture is, so the terminal's fit is exact.
    private static func pictureGrid(cellPixels: TerminalCellPixels) -> (across: Int, down: Int) {
        var factor = min(cellPixels.width, cellPixels.height)
        while factor > 1 {
            if cellPixels.width.isMultiple(of: factor), cellPixels.height.isMultiple(of: factor),
                cellPixels.width / factor >= GradientRaster.minimumPixelsPerCell,
                cellPixels.height / factor >= GradientRaster.minimumPixelsPerCell
            {
                break
            }
            factor -= 1
        }
        return (cellPixels.width / factor, cellPixels.height / factor)
    }

    private static func opaqueBytes(_ rgba: [UInt8]) -> [UInt8] {
        var rgb = [UInt8](repeating: 0, count: rgba.count / 4 * 3)
        var out = 0
        for index in stride(from: 0, to: rgba.count, by: 4) {
            rgb[out] = rgba[index]
            rgb[out + 1] = rgba[index + 1]
            rgb[out + 2] = rgba[index + 2]
            out += 3
        }
        return rgb
    }

    /// `buffer`, a picture's cells, with those whose pixels are all clear made
    /// blank and handed back to what is behind: a picture's cell hides any glyph
    /// beneath it, however clear its pixels.
    private static func punchingClearCells(
        _ buffer: FrameBuffer, raster: CanvasRaster, grid: (across: Int, down: Int), columns: Int, rows: Int
    ) -> FrameBuffer {
        var result = buffer
        for row in 0..<rows {
            var column = 0
            while column < columns {
                guard isClear(raster, column: column, row: row, grid: grid) else {
                    column += 1
                    continue
                }
                var end = column + 1
                while end < columns, isClear(raster, column: end, row: row, grid: grid) { end += 1 }
                let hole = ShapeCells(width: end - column, height: 1).buffer()
                result = result.composited(with: hole, at: (x: column, y: row))
                column = end
            }
        }
        return result
    }

    private static func isClear(_ raster: CanvasRaster, column: Int, row: Int, grid: (across: Int, down: Int)) -> Bool {
        for y in (row * grid.down)..<((row + 1) * grid.down) {
            for x in (column * grid.across)..<((column + 1) * grid.across) where raster[x, y].alpha > 0 {
                return false
            }
        }
        return true
    }
}
