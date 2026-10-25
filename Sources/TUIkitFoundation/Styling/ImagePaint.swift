//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ImagePaint.swift
//
//  A style that fills with a region of an image, repeated: `ImagePaint`, and
//  the paint it resolves to, sampled cell by cell.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIkitCore
import TUIkitStyling
import TUIkitView

// MARK: - The style

/// A shape style that fills a shape by repeating a region of an image —
/// mirrors SwiftUI's `ImagePaint`.
///
/// The region, `sourceRect`, is a rectangle in the image's unit space; it is
/// drawn at its size in points — the image's size in points times the
/// region's share of it — times `scale`, and repeated across and down from the
/// top-leading corner of what is filled, as SwiftUI repeats it (measured on
/// macOS 15.8, `Tools/SwiftUIProbes/Image paint/`). Each cell takes the
/// region's colour over the cell, averaged; a cell is a point's worth of
/// columns as the terminal's cell is points (``EnvironmentValues/imageCellPoints``),
/// so a 64-point tile in a terminal whose cell is 8 × 16 points is eight
/// columns by four rows. Where the cell's size is not known, one tile spans
/// what is filled, across, at `scale` 1. ``ShapeStyle/in(_:)`` moves where the
/// tiles start to its rectangle's origin, and its size changes nothing, as
/// SwiftUI's does.
///
/// ```swift
/// Rectangle()
///     .fill(.image(Image(.file("tile.png")), scale: 0.5))
///
/// Text("Woodgrain")
///     .foregroundStyle(ImagePaint(image: Image(.file("grain.png"))))
/// ```
///
/// An image that loads — from a file or a URL — paints nothing until its
/// pixels are there, as an ``Image`` draws its placeholder. A symbol,
/// `Image(systemName:)`, has no pixels here, being a character, and paints
/// nothing.
public struct ImagePaint: ShapeStyle {
    /// The image to be drawn.
    public var image: Image

    /// A unit-space rectangle defining how much of the source image to draw.
    /// The results are undefined if `sourceRect` selects areas outside the
    /// `[0, 1]` range in either axis.
    public var sourceRect: CGRect

    /// A scale factor applied to the image while being drawn.
    public var scale: CGFloat

    /// Creates a shape style that fills by repeating a region of `image`.
    ///
    /// - Parameters:
    ///   - image: The image to be drawn.
    ///   - sourceRect: A unit-space rectangle defining how much of the source
    ///     image to draw.
    ///   - scale: A scale factor applied to the image during rendering.
    public init(
        image: Image, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1
    ) {
        self.image = image
        self.sourceRect = sourceRect
        self.scale = scale
    }

    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .image(
            ImagePaintSource(
                content: image.content, sourceRect: sourceRect, scale: Double(scale),
                cellPoints: environment.imageCellPoints))
    }
}

extension ShapeStyle where Self == ImagePaint {
    /// A shape style that fills a shape by repeating a region of an image.
    ///
    /// - Parameters:
    ///   - image: The image to be drawn.
    ///   - sourceRect: A unit-space rectangle defining how much of the source
    ///     image to draw.
    ///   - scale: A scale factor applied to the image during rendering.
    /// - Returns: The image paint.
    public static func image(
        _ image: Image, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1
    ) -> ImagePaint {
        ImagePaint(image: image, sourceRect: sourceRect, scale: scale)
    }
}

// MARK: - The paint

/// An ``ImagePaint`` resolved: the image, the region and the scale, and — once
/// whatever draws with it has asked (`Paint.materializingImages(in:owner:)`) —
/// the image's pixels.
public struct ImagePaintSource: Equatable, Sendable {
    /// The image: a picture, or a symbol, which has no pixels.
    package var content: Image.Content
    /// The region drawn, in the image's unit space.
    package var sourceRect: CGRect
    /// The scale it is drawn at.
    package var scale: Double
    /// The strength it is drawn at, from a fade (``ShapeStyle/opacity(_:)``).
    package var opacity: Double = 1
    /// The terminal cell's size in points where this was resolved.
    package var cellPoints: TerminalCellPoints?
    /// Where the tiles start, in cells from the top-leading corner of what is
    /// filled: the origin ``ShapeStyle/in(_:)`` names.
    package var tileOrigin = CellPoint.zero
    /// The image's pixels, once asked for; `nil` while they load, and for a
    /// symbol.
    package var pixels: ImagePaintPixels?

    package init(content: Image.Content, sourceRect: CGRect, scale: Double, cellPoints: TerminalCellPoints?) {
        self.content = content
        self.sourceRect = sourceRect
        self.scale = scale
        self.cellPoints = cellPoints
    }

    /// Every stored property; the pixels by identity, so their arrival is a
    /// change to whatever compares paints — a memo below a foreground style
    /// among them — and a frame drawn with them is not mistaken for one drawn
    /// while they loaded.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.content == rhs.content && lhs.sourceRect == rhs.sourceRect && lhs.scale == rhs.scale
            && lhs.opacity == rhs.opacity && lhs.cellPoints == rhs.cellPoints && lhs.tileOrigin == rhs.tileOrigin
            && lhs.pixels === rhs.pixels
    }

    /// One colour for the paint: its pixels' mean at its strength, or nothing
    /// at all while there are none.
    var representative: Color {
        guard let pixels else { return .clear }
        return pixels.mean.opacity(opacity)
    }
}

/// An image's pixels as an ``ImagePaint`` samples them: straight RGBA, row by
/// row, and the image's size in points.
///
/// A class, shared and never changed, so a paint holding it compares by its
/// identity (``ImagePaintSource/==(_:_:)``) and copies cost nothing.
package final class ImagePaintPixels: Sendable {
    package let width: Int
    package let height: Int
    /// Four bytes a pixel — red, green, blue, alpha — row by row.
    package let rgba: [UInt8]
    /// The image's width in points.
    package let pointWidth: Double
    /// The image's height in points.
    package let pointHeight: Double
    /// The pixels' mean colour, weighted by their alpha, at their mean alpha.
    package let mean: Color
    /// Whether every pixel is opaque.
    package let isOpaque: Bool

    package init(width: Int, height: Int, rgba: [UInt8], pointWidth: Double, pointHeight: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
        let count = self.width * self.height
        self.rgba = rgba.count == count * 4 ? rgba : [UInt8](repeating: 0, count: count * 4)
        self.pointWidth = pointWidth.isFinite && pointWidth > 0 ? pointWidth : Double(max(1, width))
        self.pointHeight = pointHeight.isFinite && pointHeight > 0 ? pointHeight : Double(max(1, height))
        var sums = (red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        var opaque = true
        for index in 0..<count {
            let alpha = Double(self.rgba[index * 4 + 3])
            sums.red += Double(self.rgba[index * 4]) * alpha
            sums.green += Double(self.rgba[index * 4 + 1]) * alpha
            sums.blue += Double(self.rgba[index * 4 + 2]) * alpha
            sums.alpha += alpha
            if alpha < 255 { opaque = false }
        }
        isOpaque = opaque && count > 0
        guard sums.alpha > 0 else {
            mean = .clear
            return
        }
        func channel(_ sum: Double) -> UInt8 { UInt8(min(255, max(0, (sum / sums.alpha).rounded()))) }
        // The picture's own colour: content, not ink a palette role could name.
        let averaged = Color.rgb(channel(sums.red), channel(sums.green), channel(sums.blue))  // swiftlint:disable:this framework_colour_literal
        mean = averaged.opacity(sums.alpha / Double(count) / 255)
    }
}

// MARK: - Asking for the pixels

extension Paint {
    /// This paint with an image paint's pixels in it, asked of the image in
    /// `context` by `owner` — what whatever draws with a paint does before it
    /// samples it. A paint with no image in it is returned as it is, for one
    /// enum test.
    ///
    /// Loading a picture keeps its state — the phase, the source last loaded,
    /// the pixels — at a child identity of `context`'s, as an ``Image`` keeps
    /// its own, and the step is keyed on `owner`: the type that draws with the
    /// paint, the discriminator ``PaintAnimation`` keys on for the same
    /// reason. Several of them draw at one identity — a foreground style, the
    /// `.background` around it, a second `.background` further out — and
    /// keyed on one step they shared one load: each found the other's source
    /// the last one loaded, cancelled its load and wrote the phase back, and
    /// that write asked for another frame. Neither picture ever painted, and a
    /// still screen redrew forever.
    ///
    /// - Parameters:
    ///   - context: The context the paint draws in.
    ///   - owner: The type that draws with it: the enclosing view's, as
    ///     ``PaintAnimation/resolving(_:owner:context:)`` is told.
    @MainActor
    package func materializingImages(in context: RenderContext, owner: Any.Type) -> Paint {
        switch self {
        case .image(var source):
            guard source.pixels == nil, case .raster(let raster) = source.content else { return self }
            // A keyed step, which no view's positional child can be.
            source.pixels = raster.paintPixels(
                context: context.withChildIdentity(erasedType: owner, key: "image-paint"))
            return .image(source)
        case .shadowed(let base, let shadow):
            guard base.hasImage else { return self }
            return .shadowed(base.materializingImages(in: context, owner: owner), shadow)
        case .blended(let base, let mode):
            guard base.hasImage else { return self }
            return .blended(base.materializingImages(in: context, owner: owner), mode)
        case .frosted(let base, let frost):
            guard base.hasImage else { return self }
            return .frosted(base.materializingImages(in: context, owner: owner), frost)
        case .color, .gradient, .mesh:
            return self
        }
    }

    /// Whether an image paint is in this paint.
    var hasImage: Bool {
        switch self {
        case .image: true
        case .shadowed(let base, _): base.hasImage
        case .blended(let base, _), .frosted(let base, _): base.hasImage
        case .color, .gradient, .mesh: false
        }
    }
}
