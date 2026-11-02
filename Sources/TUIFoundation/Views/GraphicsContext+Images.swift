//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext+Images.swift
//
//  Drawing images: their pixels through the whole transform, stretched or
//  tiled.
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

// MARK: - Images

extension GraphicsContext {
    /// An image prepared for drawing — mirrors SwiftUI's
    /// `GraphicsContext.ResolvedImage`.
    public struct ResolvedImage {
        /// The image.
        let image: Image
        /// Its pixels: `nil` for a symbol, drawn in glyphs, and while a picture
        /// loads, when it has no size and draws nothing. Reading them again
        /// after the load redraws the canvas.
        let pixels: ImagePaintPixels?

        /// The image's size, in the context's units.
        public let size: CGSize
        /// The distance from the image's top to its baseline, its bottom: the
        /// baseline a cell's picture sits on.
        public let baseline: CGFloat
        /// The colour a template image is drawn in, or a symbol's. `nil` keeps
        /// what it would draw in as a view.
        public var shading: Shading?
    }

    /// `image` prepared for drawing — mirrors SwiftUI's `resolve(_:)`.
    public func resolve(_ image: Image) -> ResolvedImage {
        let views = surface.views
        let (pixels, size) = MainActor.assumeIsolated { views.prepare(image) }
        return ResolvedImage(image: image, pixels: pixels, size: size, baseline: size.height, shading: nil)
    }

    /// Draws `image` to fill `rect`, stretched to it — mirrors SwiftUI's
    /// `draw(_:in:style:)`.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - rect: Where to draw it, in the context's coordinates.
    ///   - style: The fill rule and antialiasing of the rectangle's edge.
    public func draw(_ image: ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
        guard let pixels = image.pixels else {
            let (views, width, height) = (surface.views, cellLength(rect.width), cellLength(rect.height / surface.unitsPerRow))
            let picture = image.image
            let cells = MainActor.assumeIsolated { views.cells(of: picture, width: width, height: height) }
            stamp(cells, atCellOf: rect.origin.applying(transform))
            return
        }
        let device = transform.concatenating(surface.deviceMatrix)
        let polygons = Path(rect).applying(device).contours(tolerance: Self.flattening).map(\.points)
        let inverse = device.inverted()
        let picture = pictureSource(
            pixels, rect: rect, inverse: inverse, smooth: image.image.interpolationQuality != Image.Interpolation.none,
            pixelScale: pixelScale(of: pixels, rect: rect, device: device))
        var source = picture
        if image.image.templateRenderingMode == .template {
            let ink = self.source(of: image.shading ?? .foreground, bounds: rect)
            source = .sampled { x, y in ink.colour(x, y).fading(Double(picture.colour(x, y).alpha) / 255) }
        }
        paint(source) { raster, source, opacity, mode, clip in
            raster.paint(
                polygons: polygons, evenOdd: false, antialiased: style.isAntialiased, source: source, opacity: opacity,
                mode: mode, clip: clip)
        } covering: { [surface] column, row in
            let cell = CGRect(
                x: CGFloat(column * surface.grid.across), y: CGFloat(row * surface.grid.down),
                width: CGFloat(surface.grid.across), height: CGFloat(surface.grid.down))
            let inside = CGPoint(x: cell.midX, y: cell.midY).applying(inverse)
            return rect.contains(inside) ? 1 : 0
        }
    }

    /// Draws `image` at its own size, `anchor` of it at `point` — mirrors
    /// SwiftUI's `draw(_:at:anchor:)`.
    public func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(image, in: Self.rect(of: image.size, at: point, anchor: anchor))
    }

    /// Draws `image` to fill `rect` — mirrors SwiftUI's `draw(_:in:style:)`.
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
        draw(resolve(image), in: rect, style: style)
    }

    /// Draws `image` at its own size, `anchor` of it at `point` — mirrors
    /// SwiftUI's `draw(_:at:anchor:)`.
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(image), at: point, anchor: anchor)
    }

    static func rect(of size: CGSize, at point: CGPoint, anchor: UnitPoint) -> CGRect {
        CGRect(
            x: point.x - size.width * CGFloat(anchor.x), y: point.y - size.height * CGFloat(anchor.y),
            width: size.width, height: size.height)
    }

    /// How many of the picture's pixels a pixel of the grid spans, along the
    /// worse axis.
    private func pixelScale(of pixels: ImagePaintPixels, rect: CGRect, device: CGAffineTransform) -> Double {
        let box = rect.applying(device)
        guard box.width > 0, box.height > 0 else { return 1 }
        return max(Double(pixels.width) / Double(box.width), Double(pixels.height) / Double(box.height))
    }

    /// `pixels` stretched over `rect`. A shrunk picture averages the pixels each
    /// of the grid's spans; an enlarged one blends its nearest four, unless
    /// ``Image/interpolation(_:)`` said not to.
    func pictureSource(
        _ pixels: ImagePaintPixels, rect: CGRect, inverse: CGAffineTransform, smooth: Bool, pixelScale: Double
    ) -> CanvasSource {
        guard rect.width > 0, rect.height > 0, pixels.width > 0, pixels.height > 0 else { return .flat(.clear) }
        let taps = max(1, min(4, Int(pixelScale.rounded(.up))))
        return .sampled { x, y in
            var sums = (red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
            for tapY in 0..<taps {
                for tapX in 0..<taps {
                    let point = CGPoint(
                        x: CGFloat(x) + (CGFloat(tapX) + 0.5) / CGFloat(taps),
                        y: CGFloat(y) + (CGFloat(tapY) + 0.5) / CGFloat(taps)
                    ).applying(inverse)
                    let across = Double((point.x - rect.minX) / rect.width) * Double(pixels.width)
                    let down = Double((point.y - rect.minY) / rect.height) * Double(pixels.height)
                    let colour = smooth && taps == 1 ? pixels.blended(across, down) : pixels.nearest(across, down)
                    let alpha = Double(colour.alpha)
                    sums.red += Double(colour.red) * alpha
                    sums.green += Double(colour.green) * alpha
                    sums.blue += Double(colour.blue) * alpha
                    sums.alpha += alpha
                }
            }
            guard sums.alpha > 0 else { return .clear }
            return CanvasRGBA(
                red: UInt8((sums.red / sums.alpha).rounded()), green: UInt8((sums.green / sums.alpha).rounded()),
                blue: UInt8((sums.blue / sums.alpha).rounded()), alpha: UInt8((sums.alpha / Double(taps * taps)).rounded()))
        }
    }

    // MARK: Tiling

    /// An image repeated from `origin`, for a `tiledImage` shading. A symbol, or
    /// a picture still loading, paints nothing.
    func tiledSource(_ image: Image, origin: CGPoint, sourceRect: CGRect, scale: CGFloat) -> CanvasSource {
        let views = surface.views
        let (pixels, size) = MainActor.assumeIsolated { views.prepare(image) }
        guard let pixels else { return .flat(.clear) }
        return tiled(pixels, tile: CGSize(width: size.width * scale, height: size.height * scale), origin: origin, sourceRect: sourceRect)
    }

    /// An ``ImagePaint`` as a shading: its pixels, asked for by whatever drew
    /// with it, repeated at its own size.
    func tiledSource(_ paint: ImagePaintSource) -> CanvasSource {
        var loaded = paint
        if loaded.pixels == nil, case .raster = loaded.content {
            let views = surface.views
            let materialized = MainActor.assumeIsolated {
                Paint.image(paint).materializingImages(in: views.nextImageContext(), owner: CanvasViews.self)
            }
            if case .image(let image) = materialized { loaded = image }
        }
        guard let pixels = loaded.pixels else { return .flat(.clear) }
        let size = surface.unitSize(of: pixels)
        return tiled(
            pixels, tile: CGSize(width: size.width * CGFloat(paint.scale), height: size.height * CGFloat(paint.scale)),
            origin: .zero, sourceRect: paint.sourceRect
        ).mapped { $0.fading(paint.opacity) }
    }

    private func tiled(_ pixels: ImagePaintPixels, tile: CGSize, origin: CGPoint, sourceRect: CGRect) -> CanvasSource {
        guard tile.width > 0, tile.height > 0 else { return .flat(.clear) }
        let inverse = transform.concatenating(surface.deviceMatrix).inverted()
        return .sampled { x, y in
            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5).applying(inverse)
            let across = Double((point.x - origin.x) / tile.width)
            let down = Double((point.y - origin.y) / tile.height)
            let unitX = Double(sourceRect.minX) + (across - across.rounded(.down)) * Double(sourceRect.width)
            let unitY = Double(sourceRect.minY) + (down - down.rounded(.down)) * Double(sourceRect.height)
            return pixels.nearest(unitX * Double(pixels.width), unitY * Double(pixels.height))
        }
    }
}

extension CanvasSource {
    /// The colour at (`x`, `y`).
    func colour(_ x: Int, _ y: Int) -> CanvasRGBA {
        switch self {
        case .flat(let flat): flat
        case .sampled(let sample): sample(x, y)
        }
    }
}

extension ImagePaintPixels {
    /// The pixel a point, in pixels, falls in, the edge's beyond the edge.
    func nearest(_ across: Double, _ down: Double) -> CanvasRGBA {
        pixel(x: Int(max(0, min(Double(width - 1), across.rounded(.down)))), y: Int(max(0, min(Double(height - 1), down.rounded(.down)))))
    }

    /// The four pixels nearest a point, in pixels, mixed by how near.
    func blended(_ across: Double, _ down: Double) -> CanvasRGBA {
        let (x, y) = (max(0, min(Double(width - 1), across - 0.5)), max(0, min(Double(height - 1), down - 0.5)))
        let (x0, y0) = (Int(x), Int(y))
        let (x1, y1) = (min(width - 1, x0 + 1), min(height - 1, y0 + 1))
        let (fx, fy) = (x - Double(x0), y - Double(y0))
        func mix(_ channel: KeyPath<CanvasRGBA, UInt8>) -> UInt8 {
            let top = Double(pixel(x: x0, y: y0)[keyPath: channel]) * (1 - fx) + Double(pixel(x: x1, y: y0)[keyPath: channel]) * fx
            let bottom = Double(pixel(x: x0, y: y1)[keyPath: channel]) * (1 - fx) + Double(pixel(x: x1, y: y1)[keyPath: channel]) * fx
            return UInt8((top * (1 - fy) + bottom * fy).rounded())
        }
        return CanvasRGBA(red: mix(\.red), green: mix(\.green), blue: mix(\.blue), alpha: mix(\.alpha))
    }

    private func pixel(x: Int, y: Int) -> CanvasRGBA {
        let index = (y * width + x) * 4
        return CanvasRGBA(red: rgba[index], green: rgba[index + 1], blue: rgba[index + 2], alpha: rgba[index + 3])
    }
}

extension GraphicsContext.Surface {
    /// A picture's natural size, in the context's units: its points in cells
    /// where the terminal says how big a cell is, else its pixels in cells.
    func unitSize(of pixels: ImagePaintPixels) -> CGSize {
        CanvasViews.unitSize(of: pixels, environment: environment, unitsPerRow: unitsPerRow)
    }
}
