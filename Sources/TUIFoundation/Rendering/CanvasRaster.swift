//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasRaster.swift
//
//  The pixels a `GraphicsContext` paints into: a grid of RGBA, what a polygon
//  covers of it, and how a colour lands on what is already there.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore

/// One pixel: encoded sRGB channels and a straight alpha.
struct CanvasRGBA: Equatable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    static let clear = Self(red: 0, green: 0, blue: 0, alpha: 0)

    /// This colour at `share` of its alpha.
    func fading(_ share: Double) -> Self {
        var faded = self
        faded.alpha = UInt8(max(0, min(255, (Double(alpha) * share).rounded())))
        return faded
    }
}

/// What a draw paints with, asked for its colour at a pixel of the grid.
enum CanvasSource {
    case flat(CanvasRGBA)
    case sampled((_ x: Int, _ y: Int) -> CanvasRGBA)

    /// This source with each colour through `transform`.
    func mapped(_ transform: @escaping (CanvasRGBA) -> CanvasRGBA) -> Self {
        switch self {
        case .flat(let colour): .flat(transform(colour))
        case .sampled(let sample): .sampled { transform(sample($0, $1)) }
        }
    }
}

/// Which pixels a clip keeps, and how much of each, once and for all: a new
/// clip is a new mask, so a context's copies can share one.
final class CanvasMask {
    let width: Int
    let height: Int
    private(set) var alpha: [UInt8]
    /// The pixels the mask keeps any of, `minX..<maxX` × `minY..<maxY`.
    private(set) var bounds = (minX: 0, minY: 0, maxX: 0, maxY: 0)

    /// A mask from per-pixel shares, intersected with what `previous` kept.
    init(width: Int, height: Int, previous: CanvasMask?, share: (_ x: Int, _ y: Int) -> Double) {
        self.width = width
        self.height = height
        alpha = [UInt8](repeating: 0, count: width * height)
        var seen = (minX: width, minY: height, maxX: 0, maxY: 0)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let kept = share(x, y) * Double(previous?.alpha[index] ?? 255)
                guard kept > 0 else { continue }
                alpha[index] = UInt8(min(255, kept.rounded()))
                seen = (min(seen.minX, x), min(seen.minY, y), max(seen.maxX, x + 1), max(seen.maxY, y + 1))
            }
        }
        if seen.minX < seen.maxX { bounds = seen }
    }

    /// The share of `pixel` kept.
    func share(at index: Int) -> Double { Double(alpha[index]) / 255 }

    /// The mean share kept over the block of pixels of cell (`column`, `row`).
    func meanShare(column: Int, row: Int, across: Int, down: Int) -> Double {
        var sum = 0
        for y in (row * down)..<((row + 1) * down) {
            for x in (column * across)..<((column + 1) * across) { sum += Int(alpha[y * width + x]) }
        }
        return Double(sum) / Double(across * down * 255)
    }
}

/// A rectangle of pixels: what `GraphicsContext` paints into, one for the
/// canvas and one for each layer.
///
/// A class because a context's copies draw into one destination, as SwiftUI's
/// do. Channels are straight alpha, which is what a terminal's picture is sent
/// in; they blend in encoded sRGB unless the canvas asked for linear light
/// (`ColorRenderingMode`), matching `Opacity as composition`, rule 5.
final class CanvasRaster {
    let width: Int
    let height: Int
    /// Four bytes a pixel — red, green, blue, alpha — row by row.
    private(set) var bytes: [UInt8]
    /// Whether colours decode to linear light to mix.
    let isLinear: Bool

    /// A grid of `width` × `height` pixels of `fill`.
    init(width: Int, height: Int, fill: CanvasRGBA = .clear, isLinear: Bool = false) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.isLinear = isLinear
        bytes = [UInt8](repeating: 0, count: self.width * self.height * 4)
        guard fill != .clear else { return }
        for index in stride(from: 0, to: bytes.count, by: 4) { store(fill, at: index) }
    }

    /// The pixel at (`x`, `y`), or clear outside the grid.
    subscript(x: Int, y: Int) -> CanvasRGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        return load(at: (y * width + x) * 4)
    }

    /// Whether every pixel is opaque.
    var isOpaque: Bool {
        stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }
    }

    /// Replaces the pixels, `transform` asked for each — what a filter does.
    func transformPixels(_ transform: (_ x: Int, _ y: Int, CanvasRGBA) -> CanvasRGBA) {
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                store(transform(x, y, load(at: index)), at: index)
            }
        }
    }

    @inline(__always) private func load(at index: Int) -> CanvasRGBA {
        CanvasRGBA(red: bytes[index], green: bytes[index + 1], blue: bytes[index + 2], alpha: bytes[index + 3])
    }

    @inline(__always) private func store(_ colour: CanvasRGBA, at index: Int) {
        bytes[index] = colour.red
        bytes[index + 1] = colour.green
        bytes[index + 2] = colour.blue
        bytes[index + 3] = colour.alpha
    }

    // MARK: Painting

    /// Paints `polygons`, in pixel coordinates, with `source`.
    ///
    /// Only the polygons' bounding box of the grid is walked, so a small shape
    /// on a large canvas costs what a small shape costs (``ShapeCoverage``).
    func paint(
        polygons: [[CGPoint]], evenOdd: Bool, antialiased: Bool, source: CanvasSource, opacity: Double,
        mode: GraphicsContext.BlendMode, clip: CanvasMask?
    ) {
        guard let box = Self.pixelBox(of: polygons, width: width, height: height) else { return }
        let shifted = polygons.map { polygon in
            polygon.map { CGPoint(x: $0.x - CGFloat(box.minX), y: $0.y - CGFloat(box.minY)) }
        }
        let coverage = ShapeCoverage(
            polygons: shifted, evenOdd: evenOdd, width: box.maxX - box.minX, height: box.maxY - box.minY,
            samples: Self.samplesPerSide(pixelsInBox: (box.maxX - box.minX) * (box.maxY - box.minY)))
        let whole = Double(coverage.samples * coverage.samples)
        for y in box.minY..<box.maxY {
            let base = (y - box.minY) * coverage.width
            for x in box.minX..<box.maxX {
                let count = coverage.counts[base + x - box.minX]
                guard count > 0 else { continue }
                var share = Double(count) / whole
                if !antialiased { share = share >= 0.5 ? 1 : 0 }
                guard share > 0 else { continue }
                composite(at: y * width + x, source: source, x: x, y: y, share: share * opacity, mode: mode, clip: clip)
            }
        }
    }

    /// Lays `layer`, a raster of this size, over this one at `opacity`.
    func paint(layer: CanvasRaster, opacity: Double, mode: GraphicsContext.BlendMode, clip: CanvasMask?) {
        guard layer.width == width, layer.height == height else { return }
        for y in 0..<height {
            for x in 0..<width {
                let colour = layer.load(at: (y * width + x) * 4)
                guard colour.alpha > 0 else { continue }
                composite(at: y * width + x, source: .flat(colour), x: x, y: y, share: opacity, mode: mode, clip: clip)
            }
        }
    }

    /// Paints one pixel, `share` of the way: a raw write, past any polygon.
    func paintPixel(x: Int, y: Int, source: CanvasSource, opacity: Double, mode: GraphicsContext.BlendMode, clip: CanvasMask?) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        composite(at: y * width + x, source: source, x: x, y: y, share: opacity, mode: mode, clip: clip)
    }

    private func composite(
        at pixel: Int, source: CanvasSource, x: Int, y: Int, share: Double, mode: GraphicsContext.BlendMode, clip: CanvasMask?
    ) {
        let kept = share * (clip?.share(at: pixel) ?? 1)
        guard kept > 0 else { return }
        let colour: CanvasRGBA
        switch source {
        case .flat(let flat): colour = flat
        case .sampled(let sample): colour = sample(x, y)
        }
        let index = pixel * 4
        // Nearly every pixel of an opaque shape lands here.
        if mode == .normal, kept >= 1, colour.alpha == 255 {
            store(colour, at: index)
            return
        }
        store(mode.composite(colour, share: kept, over: load(at: index), linear: isLinear), at: index)
    }

    // MARK: Geometry

    /// The pixels of a grid `polygons` may touch, or `nil` for none. A point
    /// that is not finite is left to ``ShapeCoverage``, which skips its edges.
    private static func pixelBox(
        of polygons: [[CGPoint]], width: Int, height: Int
    ) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var box = (minX: CGFloat.infinity, minY: CGFloat.infinity, maxX: -CGFloat.infinity, maxY: -CGFloat.infinity)
        for polygon in polygons {
            for point in polygon where point.x.isFinite && point.y.isFinite {
                box = (min(box.minX, point.x), min(box.minY, point.y), max(box.maxX, point.x), max(box.maxY, point.y))
            }
        }
        // Held to the grid while still floats: a far-off point lies past any
        // `Int`.
        let minX = Int(max(0, min(CGFloat(width), box.minX.rounded(.down))))
        let minY = Int(max(0, min(CGFloat(height), box.minY.rounded(.down))))
        let maxX = Int(max(0, min(CGFloat(width), box.maxX.rounded(.up))))
        let maxY = Int(max(0, min(CGFloat(height), box.maxY.rounded(.up))))
        guard box.minX <= box.maxX, minX < maxX, minY < maxY else { return nil }
        return (minX, minY, maxX, maxY)
    }

    /// The sample points along a pixel's side: four, as a shape's half blocks
    /// are measured at, and two over the many pixels of a terminal's picture,
    /// where a pixel is too small to see the difference and a fill would pay
    /// for it four times over.
    private static func samplesPerSide(pixelsInBox: Int) -> Int {
        pixelsInBox > 40_000 ? 2 : 4
    }
}

// MARK: - Blending

extension GraphicsContext.BlendMode {
    /// `source` laid over `backdrop` by this mode, `share` of the way: the
    /// antialiased edge of a shape, a clip's, a layer's opacity.
    ///
    /// The separable and HSL modes mix as ``TUICore/BlendMode`` does for a view
    /// (W3C compositing: the mixed colour, by the backdrop's alpha, then source
    /// over). The Porter-Duff operators weigh source and backdrop by the pair
    /// `(Fa, Fb)` of their table.
    func composite(_ source: CanvasRGBA, share: Double, over backdrop: CanvasRGBA, linear: Bool) -> CanvasRGBA {
        let sa = Double(source.alpha) / 255
        let ba = Double(backdrop.alpha) / 255
        let cs = Self.channels(of: source, linear: linear)
        let cb = Self.channels(of: backdrop, linear: linear)
        if let weights = porterDuffWeights(sa: sa, ba: ba) {
            // A whole colour by its table's weights, then `share` of the way
            // from the backdrop: outside a shape, nothing changes.
            let outA = sa * weights.0 + ba * weights.1
            func channel(_ s: Double, _ b: Double) -> Double {
                let drawn = s * sa * weights.0 + b * ba * weights.1
                return drawn * share + b * ba * (1 - share)
            }
            let alpha = outA * share + ba * (1 - share)
            return Self.pixel(channel(cs.red, cb.red), channel(cs.green, cb.green), channel(cs.blue, cb.blue), alpha, linear)
        }
        let a = sa * share
        if self == .plusLighter || self == .plusDarker {
            let alpha = min(1, a + ba)
            func channel(_ s: Double, _ b: Double) -> Double {
                let sum = s * a + b * ba
                return self == .plusLighter ? min(alpha, sum) : max(0, sum - (a + ba - alpha))
            }
            return Self.pixel(channel(cs.red, cb.red), channel(cs.green, cb.green), channel(cs.blue, cb.blue), alpha, linear)
        }
        let mixed = ba > 0 ? (viewMode?.blended(cs, over: cb) ?? cs) : cs
        func channel(_ s: Double, _ m: Double, _ b: Double) -> Double {
            let drawn = (1 - ba) * s + ba * min(1, max(0, m))
            return a * drawn + ba * (1 - a) * b
        }
        let alpha = a + ba * (1 - a)
        return Self.pixel(
            channel(cs.red, mixed.red, cb.red), channel(cs.green, mixed.green, cb.green),
            channel(cs.blue, mixed.blue, cb.blue), alpha, linear)
    }

    /// The Porter-Duff weights `(Fa, Fb)`, for the modes that are those.
    private func porterDuffWeights(sa: Double, ba: Double) -> (Double, Double)? {
        switch self {
        case .clear: (0, 0)
        case .copy: (1, 0)
        case .sourceIn: (ba, 0)
        case .sourceOut: (1 - ba, 0)
        case .sourceAtop: (ba, 1 - sa)
        case .destinationOver: (1 - ba, 1)
        case .destinationIn: (0, sa)
        case .destinationOut: (0, 1 - sa)
        case .destinationAtop: (1 - ba, sa)
        case .xor: (1 - ba, 1 - sa)
        default: nil
        }
    }

    /// The mode a view blends by that mixes as this one does: the one blend
    /// table (`BlendMode.blended(_:over:)`), measured against macOS.
    private var viewMode: TUICore.BlendMode? {
        switch self {
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .darken: .darken
        case .lighten: .lighten
        case .colorDodge: .colorDodge
        case .colorBurn: .colorBurn
        case .softLight: .softLight
        case .hardLight: .hardLight
        case .difference: .difference
        case .exclusion: .exclusion
        case .hue: .hue
        case .saturation: .saturation
        case .color: .color
        case .luminosity: .luminosity
        default: nil
        }
    }

    private static func channels(of colour: CanvasRGBA, linear: Bool) -> TUICore.BlendMode.Channels {
        (decode(colour.red, linear), decode(colour.green, linear), decode(colour.blue, linear))
    }

    private static func decode(_ channel: UInt8, _ linear: Bool) -> Double {
        let encoded = Double(channel) / 255
        guard linear else { return encoded }
        return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    /// Premultiplied channels and their alpha, as a pixel.
    private static func pixel(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double, _ linear: Bool) -> CanvasRGBA {
        guard alpha > 0 else { return .clear }
        func encode(_ premultiplied: Double) -> UInt8 {
            var value = min(1, max(0, premultiplied / alpha))
            if linear { value = value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055 }
            return UInt8((value * 255).rounded())
        }
        return CanvasRGBA(
            red: encode(red), green: encode(green), blue: encode(blue), alpha: UInt8((min(1, alpha) * 255).rounded()))
    }
}
