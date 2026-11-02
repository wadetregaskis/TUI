//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext+Surface.swift
//
//  What a `GraphicsContext` draws into: cells for glyphs and, once something
//  paints, pixels beneath them.
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

extension GraphicsContext {
    /// What a context draws into, shared by its copies: each glyph written, the
    /// last write to a cell winning, as later drawing covers earlier; and the
    /// pixels paths and images paint.
    final class Surface {
        struct Cell: Equatable {
            var character: String
            var width: Int
            var style: SGRState
            var opacity: Double
            /// When it was written, among everything drawn on this surface.
            var serial = 0
        }

        /// Row → column → cell.
        private(set) var rows: [Int: [Int: Cell]] = [:]

        /// How far past a text's frame a glyph may be drawn, in columns and
        /// rows: farther is past any screen a person reads, and the buffer
        /// made from the surface spans every cell between, so a renderer that
        /// translated by `1 / sin(t)` near zero would otherwise allocate
        /// millions of rows a frame.
        static let reach = (columns: 256, rows: 128)

        /// The rectangle a glyph's origin must lie in: the frame, and for a
        /// text ``reach`` round it.
        private let bounds: (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat)

        /// The frame, in cells.
        let frame: (columns: Int, rows: Int)
        /// How many of the context's units a row is tall: the cell aspect in a
        /// ``Canvas``, whose units are a shape's, and 1 in a text, whose are its
        /// layout's.
        let unitsPerRow: CGFloat
        /// A cell's pixels.
        let grid: (across: Int, down: Int)
        /// The grain the pixels become cells at, where they do.
        let grain: CanvasGrain
        /// What text, images and symbols are drawn through.
        let views: CanvasViews
        /// The container values of the canvas's symbols, in their order: what
        /// a symbol's tag is looked up in, with no actor to hop to.
        let symbolValues: [ContainerValues]
        /// The view's environment.
        let environment: EnvironmentValues
        /// What a canvas's pixels start as, where it said it is opaque.
        private let backdrop: CanvasRGBA?
        /// Whether colours mix in linear light (`ColorRenderingMode`).
        private let isLinear: Bool

        /// The pixels, once anything paints: a text that only draws glyphs, and
        /// a canvas that only writes them, make none.
        private(set) lazy var raster = CanvasRaster(
            width: frame.columns * grid.across, height: frame.rows * grid.down, fill: backdrop ?? .clear, isLinear: isLinear)
        private(set) var hasPaint = false

        /// Whether something was painted with a colour that has no channels,
        /// which a picture cannot hold.
        private(set) var hasColourWithoutChannels = false
        /// The colour a pixel's channels stand for, for each colour painted that
        /// has none of its own: the cells can spell it, as a pixel cannot.
        private(set) var spelling: [UInt32: Color] = [:]

        private var lastSerial = 0

        /// A surface for a text whose frame is `width` × `height` cells. Units
        /// are cells, and a glyph may land past the frame, by ``reach``.
        @MainActor init(textOf width: Int, _ height: Int, context: RenderContext) {
            bounds = (
                CGFloat(-Self.reach.columns), CGFloat(-Self.reach.rows),
                CGFloat(width + Self.reach.columns), CGFloat(height + Self.reach.rows))
            frame = (width, height)
            unitsPerRow = 1
            grain = context.environment.canvasGrain
            grid = grain.cellPixels
            views = CanvasViews(context: context, unitsPerRow: 1)
            symbolValues = []
            environment = context.environment
            backdrop = nil
            isLinear = false
        }

        /// A surface for a canvas of `columns` × `rows` cells at `grid` pixels
        /// a cell. A glyph lands inside the frame or nowhere: a canvas clips to
        /// its frame.
        @MainActor init(
            canvasOf columns: Int, _ rows: Int, unitsPerRow: Double, grid: (across: Int, down: Int), grain: CanvasGrain,
            backdrop: CanvasRGBA?, isLinear: Bool, symbols: [Subview], context: RenderContext
        ) {
            bounds = (0, 0, CGFloat(columns), CGFloat(rows))
            frame = (columns, rows)
            self.unitsPerRow = CGFloat(unitsPerRow)
            self.grid = grid
            self.grain = grain
            self.backdrop = backdrop
            self.isLinear = isLinear
            views = CanvasViews(context: context, unitsPerRow: CGFloat(unitsPerRow), symbols: symbols)
            symbolValues = symbols.map(\.containerValues)
            environment = context.environment
        }

        /// From the context's units past its transform to pixels of the grid.
        var deviceMatrix: CGAffineTransform {
            CGAffineTransform(scaleX: CGFloat(grid.across), y: CGFloat(grid.down) / unitsPerRow)
        }

        func nextSerial() -> Int {
            lastSerial += 1
            return lastSerial
        }

        /// Says the surface's own pixels have been painted.
        func notePaint() { hasPaint = true }

        /// `color` as a pixel: its channels, or a stand-in for them where the
        /// terminal decides it and has not said (``Color/rgbComponents``).
        func pixel(of color: Color) -> CanvasRGBA {
            let resolved = color.resolve(with: environment.palette)
            if let rgb = resolved.rgbComponents {
                return CanvasRGBA(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: resolved.alpha)
            }
            hasColourWithoutChannels = true
            // A stand-in the pixels mix with, and that the cells swap back. Its
            // own value only shows where it was mixed with something else.
            let spelled = resolved.opaqueSpelling
            var stand = (red: UInt8(192), green: UInt8(192), blue: UInt8(192))
            if let known = spelling.first(where: { $0.value == spelled })?.key {
                stand = (UInt8(known >> 16 & 0xFF), UInt8(known >> 8 & 0xFF), UInt8(known & 0xFF))
            } else {
                // A channel apart per colour, so two stand-ins are two colours.
                stand.blue &+= UInt8(truncatingIfNeeded: spelling.count)
                spelling[UInt32(stand.red) << 16 | UInt32(stand.green) << 8 | UInt32(stand.blue)] = spelled
            }
            return CanvasRGBA(red: stand.red, green: stand.green, blue: stand.blue, alpha: resolved.alpha)
        }

        // MARK: Glyphs

        /// Whether a glyph at `origin`, in cells, is drawn: inside ``bounds``,
        /// which a non-finite coordinate never is.
        func reaches(_ origin: CGPoint) -> Bool {
            origin.x >= bounds.minX && origin.x <= bounds.maxX && origin.y >= bounds.minY && origin.y <= bounds.maxY
        }

        func write(_ cell: Cell, column: Int, row: Int) {
            guard cell.opacity > 0 else { return }
            var line = rows[row] ?? [:]
            // A wide glyph covers the cell after it, and a glyph written over
            // either half of a wide one removes it.
            if let before = line[column - 1], before.width > 1 { line[column - 1] = nil }
            for covered in column..<(column + cell.width) where covered != column { line[covered] = nil }
            line[column] = cell
            rows[row] = line
        }

        /// Removes the glyphs older than `serial` whose cell `share` says was
        /// painted at least half over. A glyph and pixels cannot share a cell,
        /// so whichever was drawn over the other takes it.
        func coverGlyphs(olderThan serial: Int, share: (_ column: Int, _ row: Int) -> Double) {
            guard !rows.isEmpty else { return }
            for (row, line) in rows {
                var kept = line
                for (column, cell) in line where cell.serial < serial && share(column, row) >= 0.5 {
                    kept[column] = nil
                }
                rows[row] = kept
            }
        }

        /// The extent drawn: the smallest rectangle holding every cell
        /// written and the frame, `width` × `height` at the origin.
        func extent(including width: Int, _ height: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
            var extent = (minX: 0, minY: 0, maxX: width, maxY: height)
            for (row, line) in rows {
                for (column, cell) in line {
                    extent.minX = min(extent.minX, column)
                    extent.maxX = max(extent.maxX, column + cell.width)
                    extent.minY = min(extent.minY, row)
                    extent.maxY = max(extent.maxY, row + 1)
                }
            }
            return extent
        }

        /// The cells as a buffer covering `extent`, its top-left the
        /// extent's, with the fade each cell was drawn at claimed for the
        /// compositor (`OpacityRegion`), and a cell nothing was drawn in left
        /// blank: what is beneath shows there.
        func buffer(covering extent: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> FrameBuffer {
            var lines: [String] = []
            var widths: [Int] = []
            var claims: [OpacityRegion] = []
            for row in extent.minY..<extent.maxY {
                let drawn = line(row: row, from: extent.minX, to: extent.maxX)
                lines.append(drawn.text)
                widths.append(max(drawn.width, extent.maxX - extent.minX))
                for var claim in drawn.claims {
                    claim.offsetY = row - extent.minY
                    claims.append(claim)
                }
            }
            var buffer = FrameBuffer(lines: lines, width: extent.maxX - extent.minX, lineWidths: widths)
            buffer.opacityRegions = claims
            return buffer
        }

        /// Row `row` of the cells between two columns: the text, the width to
        /// its last glyph, and the fades owed, each claimed at row 0.
        private func line(row: Int, from start: Int, to end: Int) -> (text: String, width: Int, claims: [OpacityRegion]) {
            var line = ""
            var state = SGRState()
            var column = start
            var drawnWidth = 0
            var claims: [OpacityRegion] = []
            let cells = rows[row] ?? [:]
            while column < end {
                guard let cell = cells[column] else {
                    if !state.isDefault {
                        line += "\u{1B}[0m"
                        state = SGRState()
                    }
                    line += " "
                    column += 1
                    continue
                }
                line += cell.style.rendered(changingFrom: state)
                state = cell.style
                line += cell.character
                if cell.opacity < 1 {
                    claims.append(
                        OpacityRegion(offsetX: column - start, offsetY: 0, width: cell.width, height: 1, opacity: cell.opacity))
                }
                column += cell.width
                drawnWidth = column - start
            }
            if !state.isDefault { line += "\u{1B}[0m" }
            return (line, drawnWidth, claims)
        }

        /// `base`, whose top-left is cell (`origin.x`, `origin.y`), with every
        /// run of glyphs laid over it. A run alone, so a cell no glyph was
        /// written in stays `base`'s, and a glyph with no field of its own takes
        /// the one beneath it (``FrameBuffer/composited(with:at:)``).
        func glyphs(over base: FrameBuffer, origin: (x: Int, y: Int) = (0, 0)) -> FrameBuffer {
            var result = base
            for (row, cells) in rows.sorted(by: { $0.key < $1.key }) {
                var column = cells.keys.min() ?? 0
                let last = cells.keys.max() ?? -1
                while column <= last {
                    guard cells[column] != nil else {
                        column += 1
                        continue
                    }
                    var end = column
                    while let cell = cells[end] { end += cell.width }
                    let run = line(row: row, from: column, to: end)
                    var overlay = FrameBuffer(lines: [run.text], width: end - column, lineWidths: [end - column])
                    overlay.opacityRegions = run.claims
                    result = result.composited(with: overlay, at: (x: column - origin.x, y: row - origin.y))
                    column = end
                }
            }
            return result
        }

        /// The surface as a buffer covering `extent`: the glyphs alone where
        /// nothing painted, or over the pixels' cells.
        func bufferOverPixels(covering extent: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> FrameBuffer {
            guard hasPaint else { return buffer(covering: extent) }
            let cells = pixelCells(monochrome: ColorDepth.current == .noColor).buffer()
            var base = cells
            if extent.minX != 0 || extent.minY != 0 || extent.maxX != frame.columns || extent.maxY != frame.rows {
                let width = extent.maxX - extent.minX
                let blank = String(repeating: " ", count: width)
                base = FrameBuffer(
                    lines: Array(repeating: blank, count: extent.maxY - extent.minY), width: width,
                    lineWidths: Array(repeating: width, count: extent.maxY - extent.minY))
                base = base.composited(with: cells, at: (x: -extent.minX, y: -extent.minY))
            }
            return glyphs(over: base, origin: (extent.minX, extent.minY))
        }

        /// The pixels as cells at the grain.
        func pixelCells(monochrome: Bool) -> ShapeCells {
            CanvasCells.cells(
                of: raster, grain: grain, columns: frame.columns, rows: frame.rows, monochrome: monochrome, backdrop: backdrop,
                spelling: spelling)
        }
    }
}
