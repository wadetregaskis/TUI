//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageTileRaster.swift
//
//  An image paint's colour at each cell: the image's region, repeated from
//  the extent's top-leading corner, averaged over the cell.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIStyling

/// An ``ImagePaint``'s cells, for ``SampledCells``: the image's region, a tile
/// of it repeated across and down from the extent's top-leading corner — or
/// from the origin ``ShapeStyle/in(_:)`` names, measured from that corner —
/// each cell the mean of a few samples of it.
///
/// Laid out in square units, a column wide, as a shape is: a row is
/// `cellAspect` of them tall, so the half-cell sampler a shape's rasterizer
/// asks (half the aspect, twice the rows) sees the same picture at twice the
/// height resolution. The tile is its size in points over the cell's width in
/// points; where the cell's size is not known, one tile spans the extent
/// across, at its own aspect.
struct ImageTileRaster: CellColourRaster {
    /// How many samples a cell takes along each axis.
    static let samplesPerAxis = 2

    /// The farthest, in cells, a tile origin moves the tiles: well past any
    /// screen, and far enough from `Int`'s ends that no arithmetic on a cell's
    /// place overflows. Only where a tile starts within the fill matters.
    static let tileOriginLimit = 1 << 20

    private let pixels: ImagePaintPixels
    /// The region of the image drawn, in pixels: origin and size.
    private let region: (x: Double, y: Double, width: Double, height: Double)
    /// A tile's size in square units.
    private let tile: (width: Double, height: Double)
    /// A row's height in square units.
    private let rowHeight: Double
    /// Where the block drawn starts, in cells from where the tiles do: its
    /// place in the extent, less the tile origin ``ShapeStyle/in(_:)`` names.
    private let origin: (x: Int, y: Int)
    private let opacity: Double

    /// The raster of `source` over `extent`, or `nil` with no pixels to draw:
    /// still loading, a symbol, an image or a region with no area.
    init?(_ source: ImagePaintSource, extent: GradientFrame, cellAspect: Double) {
        guard let pixels = source.pixels, pixels.width > 0, pixels.height > 0 else { return nil }
        func unit(_ value: CGFloat) -> Double { min(1, max(0, Double(value).isNaN ? 0 : Double(value))) }
        let rect = source.sourceRect.standardized
        let (left, top, right, bottom) = (unit(rect.minX), unit(rect.minY), unit(rect.maxX), unit(rect.maxY))
        guard right > left, bottom > top else { return nil }
        self.pixels = pixels
        region = (
            left * Double(pixels.width), top * Double(pixels.height),
            (right - left) * Double(pixels.width), (bottom - top) * Double(pixels.height)
        )
        let scale = source.scale.isFinite && source.scale > 0 ? source.scale : 1
        let points = (
            width: pixels.pointWidth * (right - left) * scale, height: pixels.pointHeight * (bottom - top) * scale
        )
        if let cell = source.cellPoints {
            tile = (points.width / cell.width, points.height / cell.width)
        } else {
            let across = Double(max(1, extent.width)) * scale
            tile = (across, across * points.height / points.width)
        }
        guard tile.width.isFinite, tile.height.isFinite, tile.width > 0, tile.height > 0 else { return nil }
        rowHeight = cellAspect.isFinite && cellAspect > 0 ? cellAspect : 2
        func clamped(_ value: Int) -> Int { min(Self.tileOriginLimit, max(-Self.tileOriginLimit, value)) }
        origin = (
            clamped(extent.originX) - clamped(source.tileOrigin.x), clamped(extent.originY) - clamped(source.tileOrigin.y)
        )
        opacity = min(1, max(0, source.opacity))
    }

    func colours(columns: Range<Int>, rows: Range<Int>) -> [Color] {
        var colours: [Color] = []
        colours.reserveCapacity(columns.count * rows.count)
        for row in rows {
            for column in columns {
                colours.append(colour(column: origin.x + column, row: origin.y + row))
            }
        }
        return colours
    }

    /// The mean of the cell's samples, their colours weighted by their alpha.
    private func colour(column: Int, row: Int) -> Color {
        let count = Self.samplesPerAxis
        var sums = (red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        for step in 0..<(count * count) {
            let x = Double(column) + (Double(step % count) + 0.5) / Double(count)
            let y = (Double(row) + (Double(step / count) + 0.5) / Double(count)) * rowHeight
            let index = pixelIndex(x: x, y: y)
            let alpha = Double(pixels.rgba[index + 3])
            sums.red += Double(pixels.rgba[index]) * alpha
            sums.green += Double(pixels.rgba[index + 1]) * alpha
            sums.blue += Double(pixels.rgba[index + 2]) * alpha
            sums.alpha += alpha
        }
        guard sums.alpha > 0 else { return .clear }
        func channel(_ sum: Double) -> UInt8 { UInt8(min(255, max(0, (sum / sums.alpha).rounded()))) }
        // The picture's own colour: content, not ink a palette role could name.
        let sampled = Color.rgb(channel(sums.red), channel(sums.green), channel(sums.blue))  // swiftlint:disable:this framework_colour_literal
        return sampled.opacity(sums.alpha / Double(count * count) / 255 * opacity)
    }

    /// The byte offset of the pixel under the point `x`, `y`, in square units
    /// from the extent's top-leading corner.
    private func pixelIndex(x: Double, y: Double) -> Int {
        let across = x / tile.width
        let down = y / tile.height
        let alongTile = across - across.rounded(.down)
        let downTile = down - down.rounded(.down)
        let column = min(pixels.width - 1, max(0, Int(region.x + alongTile * region.width)))
        let row = min(pixels.height - 1, max(0, Int(region.y + downTile * region.height)))
        return (row * pixels.width + column) * 4
    }
}
