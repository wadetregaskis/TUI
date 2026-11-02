//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext+Drawing.swift
//
//  Painting paths, clipping, blending and layers: the half of SwiftUI's
//  `GraphicsContext` that lands on a canvas's pixels.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIStyling

extension GraphicsContext {
    // MARK: Blend modes

    /// How what a context draws combines with what it lands on — mirrors
    /// SwiftUI's `GraphicsContext.BlendMode`, its raw values `CGBlendMode`'s.
    public struct BlendMode: RawRepresentable, Equatable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static var normal: Self { Self(rawValue: 0) }
        public static var multiply: Self { Self(rawValue: 1) }
        public static var screen: Self { Self(rawValue: 2) }
        public static var overlay: Self { Self(rawValue: 3) }
        public static var darken: Self { Self(rawValue: 4) }
        public static var lighten: Self { Self(rawValue: 5) }
        public static var colorDodge: Self { Self(rawValue: 6) }
        public static var colorBurn: Self { Self(rawValue: 7) }
        public static var softLight: Self { Self(rawValue: 8) }
        public static var hardLight: Self { Self(rawValue: 9) }
        public static var difference: Self { Self(rawValue: 10) }
        public static var exclusion: Self { Self(rawValue: 11) }
        public static var hue: Self { Self(rawValue: 12) }
        public static var saturation: Self { Self(rawValue: 13) }
        public static var color: Self { Self(rawValue: 14) }
        public static var luminosity: Self { Self(rawValue: 15) }
        public static var clear: Self { Self(rawValue: 16) }
        public static var copy: Self { Self(rawValue: 17) }
        public static var sourceIn: Self { Self(rawValue: 18) }
        public static var sourceOut: Self { Self(rawValue: 19) }
        public static var sourceAtop: Self { Self(rawValue: 20) }
        public static var destinationOver: Self { Self(rawValue: 21) }
        public static var destinationIn: Self { Self(rawValue: 22) }
        public static var destinationOut: Self { Self(rawValue: 23) }
        public static var destinationAtop: Self { Self(rawValue: 24) }
        public static var xor: Self { Self(rawValue: 25) }
        public static var plusDarker: Self { Self(rawValue: 26) }
        public static var plusLighter: Self { Self(rawValue: 27) }
    }

    // MARK: Filling and stroking

    /// Draws `path` into the context by filling it — mirrors SwiftUI's
    /// `fill(_:with:style:)`.
    ///
    /// - Parameters:
    ///   - path: The path to fill.
    ///   - shading: The colour or pattern to fill it with.
    ///   - style: The fill rule and antialiasing.
    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        let device = transform.concatenating(surface.deviceMatrix)
        let polygons = path.applying(device).contours(tolerance: Self.flattening).map(\.points)
        paint(
            polygons: polygons, evenOdd: style.isEOFilled, antialiased: style.isAntialiased,
            shading: shading, bounds: path.boundingRect)
    }

    /// Draws `path` into the context by stroking it — mirrors SwiftUI's
    /// `stroke(_:with:style:)`. The line's width and dashes are in the context's
    /// units, so a transform scales them, as SwiftUI's does.
    ///
    /// - Parameters:
    ///   - path: The path to stroke.
    ///   - shading: The colour or pattern to stroke it with.
    ///   - style: The stroke's width, caps, joins and dashes.
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        let device = transform.concatenating(surface.deviceMatrix)
        let scale = max(abs(device.a) + abs(device.c), abs(device.b) + abs(device.d), 0.001)
        let contours = path.contours(tolerance: Self.flattening / scale)
        let polygons = ShapeStroker.polygons(of: contours, style: style).map { polygon in
            polygon.map { $0.applying(device) }
        }
        paint(polygons: polygons, evenOdd: false, antialiased: true, shading: shading, bounds: path.boundingRect)
    }

    /// Draws `path` into the context by stroking it `lineWidth` wide — mirrors
    /// SwiftUI's `stroke(_:with:lineWidth:)`.
    ///
    /// - Parameters:
    ///   - path: The path to stroke.
    ///   - shading: The colour or pattern to stroke it with.
    ///   - lineWidth: The line's width, in the context's units.
    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    /// Curves straight to within a twentieth of a pixel of the grid, as a
    /// rasterized shape's are: finer than a pixel's samples.
    static var flattening: CGFloat { 0.05 }

    // MARK: Painting

    /// The raster paths land on.
    var target: CanvasRaster { layer ?? surface.raster }

    /// `polygons`, in pixels, painted with `shading` under this context's state.
    func paint(polygons: [[CGPoint]], evenOdd: Bool, antialiased: Bool, shading: Shading, bounds: CGRect) {
        paint(source(of: shading, bounds: bounds)) { raster, source, opacity, mode, clip in
            raster.paint(
                polygons: polygons, evenOdd: evenOdd, antialiased: antialiased, source: source, opacity: opacity,
                mode: mode, clip: clip)
        } covering: { column, row in
            // What the drawing covers of a cell, asked only where a glyph is.
            Self.cellShare(of: polygons, evenOdd: evenOdd, grid: surface.grid, column: column, row: row)
        }
    }

    /// `source` drawn by `draw` under this context's state: straight into the
    /// raster, its colours through the colour filters; or, where a filter needs
    /// the drawing's pixels, into a layer of its own that lands whole.
    func paint(
        _ source: CanvasSource,
        draw: (_ raster: CanvasRaster, _ source: CanvasSource, _ opacity: Double, _ mode: BlendMode, _ clip: CanvasMask?) -> Void,
        covering share: (_ column: Int, _ row: Int) -> Double
    ) {
        let raster = target
        if layer == nil { surface.notePaint() }
        if filters.contains(where: \.needsPixels) {
            let drawing = CanvasRaster(width: raster.width, height: raster.height, isLinear: raster.isLinear)
            draw(drawing, source, 1, .normal, nil)
            let landed = applyingFilters(to: drawing)
            raster.paint(layer: landed, opacity: opacity, mode: blendMode, clip: clipMask)
            coverGlyphs(by: landed)
            return
        }
        let mapped = filters.isEmpty ? source : source.mapped { filtered($0) }
        draw(raster, mapped, opacity, blendMode, clipMask)
        // A layer covers what is older when it lands, not as it is drawn: what
        // it holds so far is not yet over anything.
        guard layer == nil else { return }
        surface.coverGlyphs(olderThan: Int.max) { column, row in
            share(column, row) * clippedShare(column: column, row: row)
        }
    }

    /// The share of a cell the clip keeps.
    func clippedShare(column: Int, row: Int) -> Double {
        guard let clipMask else { return 1 }
        let grid = surface.grid
        guard column >= 0, row >= 0, (column + 1) * grid.across <= clipMask.width, (row + 1) * grid.down <= clipMask.height
        else { return 0 }
        return clipMask.meanShare(column: column, row: row, across: grid.across, down: grid.down)
    }

    /// Takes glyphs under `drawing`'s pixels off the surface: those older than
    /// this context's layer, or any at all with no layer.
    func coverGlyphs(by drawing: CanvasRaster) {
        guard layer == nil else { return }
        coverGlyphs(by: drawing, olderThan: Int.max)
    }

    private func coverGlyphs(by drawing: CanvasRaster, olderThan serial: Int) {
        let grid = surface.grid
        surface.coverGlyphs(olderThan: serial) { column, row in
            guard column >= 0, row >= 0, (column + 1) * grid.across <= drawing.width, (row + 1) * grid.down <= drawing.height
            else { return 0 }
            var there = 0
            for y in (row * grid.down)..<((row + 1) * grid.down) {
                for x in (column * grid.across)..<((column + 1) * grid.across) where drawing[x, y].alpha >= 128 {
                    there += 1
                }
            }
            return Double(there) / Double(grid.across * grid.down)
        }
    }

    /// The share of cell (`column`, `row`) `polygons`, in pixels, cover.
    private static func cellShare(
        of polygons: [[CGPoint]], evenOdd: Bool, grid: (across: Int, down: Int), column: Int, row: Int
    ) -> Double {
        let cell = polygons.map { polygon in
            polygon.map {
                CGPoint(x: $0.x / CGFloat(grid.across) - CGFloat(column), y: $0.y / CGFloat(grid.down) - CGFloat(row))
            }
        }
        return ShapeCoverage(polygons: cell, evenOdd: evenOdd, width: 1, height: 1).coverage(x: 0, y: 0)
    }

    /// `colour` through this context's colour filters.
    func filtered(_ colour: CanvasRGBA) -> CanvasRGBA {
        // The drawing's own colour, filtered: content, not a framework ink.
        // swiftlint:disable:next framework_colour_literal
        var color = Color.rgb(colour.red, colour.green, colour.blue)
        for filter in filters where !filter.needsPixels { color = filter.applied(to: color) }
        guard let rgb = color.rgbComponents else { return colour }
        return CanvasRGBA(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: colour.alpha)
    }

    // MARK: Clipping

    /// Options for a clip — mirrors SwiftUI's `GraphicsContext.ClipOptions`.
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Keeps what the clip's shape does not cover.
        public static var inverse: Self { Self(rawValue: 1) }
    }

    /// The bounding rectangle of the clip in force, in this context's
    /// coordinates — mirrors SwiftUI's `clipBoundingRect`.
    public var clipBoundingRect: CGRect {
        let grid = surface.grid
        let box =
            clipMask?.bounds
            ?? (minX: 0, minY: 0, maxX: surface.frame.columns * grid.across, maxY: surface.frame.rows * grid.down)
        let rect = CGRect(
            x: CGFloat(box.minX), y: CGFloat(box.minY), width: CGFloat(box.maxX - box.minX), height: CGFloat(box.maxY - box.minY))
        return rect.applying(transform.concatenating(surface.deviceMatrix).inverted())
    }

    /// Clips what this context draws next to `path` — mirrors SwiftUI's
    /// `clip(to:style:options:)`.
    ///
    /// A glyph is not cut: it is drawn where the clip keeps at least half of its
    /// cell, and not otherwise.
    ///
    /// - Parameters:
    ///   - path: The path to clip to.
    ///   - style: The fill rule and antialiasing.
    ///   - options: Whether to keep the outside instead.
    public mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = ClipOptions()) {
        let raster = target
        let device = transform.concatenating(surface.deviceMatrix)
        let polygons = path.applying(device).contours(tolerance: Self.flattening).map(\.points)
        let coverage = ShapeCoverage(polygons: polygons, evenOdd: style.isEOFilled, width: raster.width, height: raster.height)
        let (inverse, antialiased) = (options.contains(.inverse), style.isAntialiased)
        clipMask = CanvasMask(width: raster.width, height: raster.height, previous: clipMask) { x, y in
            var share = coverage.coverage(x: x, y: y)
            if !antialiased { share = share >= 0.5 ? 1 : 0 }
            return inverse ? 1 - share : share
        }
    }

    /// Clips what this context draws next to the alpha of what `content` draws
    /// into a new layer — mirrors SwiftUI's `clipToLayer(opacity:options:content:)`.
    ///
    /// - Parameters:
    ///   - opacity: The strength the layer clips at.
    ///   - options: Whether to keep what the layer does not draw instead.
    ///   - content: Draws the layer. Its glyphs clip nothing.
    public mutating func clipToLayer(
        opacity: Double = 1, options: ClipOptions = ClipOptions(), content: (inout Self) throws -> Void
    ) rethrows {
        let drawn = try layerDrawing(content: content)
        let inverse = options.contains(.inverse)
        clipMask = CanvasMask(width: drawn.width, height: drawn.height, previous: clipMask) { x, y in
            let share = Double(drawn[x, y].alpha) / 255 * opacity
            return inverse ? 1 - share : share
        }
    }

    // MARK: Layers

    /// Draws `content` into a new transparency layer of this context's, and then
    /// the layer into this context as one drawing, through its opacity, filters,
    /// blend mode and clip — mirrors SwiftUI's `drawLayer(content:)`.
    ///
    /// The transform carries in. A glyph has no layer to blend in, so one drawn
    /// inside takes this context's opacity and filters in its own cell at once.
    ///
    /// - Parameter content: Draws the layer.
    public func drawLayer(content: (inout Self) throws -> Void) rethrows {
        let start = surface.nextSerial()
        let drawn = try layerDrawing(content: content)
        let raster = target
        if layer == nil { surface.notePaint() }
        let landed = filters.contains(where: \.needsPixels) ? applyingFilters(to: drawn) : drawn
        if !filters.isEmpty, !filters.contains(where: \.needsPixels) {
            landed.transformPixels { _, _, colour in colour.alpha == 0 ? colour : filtered(colour) }
        }
        raster.paint(layer: landed, opacity: opacity, mode: blendMode, clip: clipMask)
        // Covered as it lands: a glyph the layer itself drew is on top of it.
        if layer == nil { coverGlyphs(by: landed, olderThan: start) }
    }

    /// What `content` draws, in a raster of its own.
    private func layerDrawing(content: (inout Self) throws -> Void) rethrows -> CanvasRaster {
        let raster = target
        var inner = self
        inner.layer = CanvasRaster(width: raster.width, height: raster.height, isLinear: raster.isLinear)
        inner.opacity = 1
        inner.filters = []
        inner.blendMode = .normal
        inner.clipMask = nil
        inner.enclosing = (opacity * enclosing.opacity, filters + enclosing.filters)
        try content(&inner)
        return inner.layer ?? raster
    }
}
