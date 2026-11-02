//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext+Filters.swift
//
//  SwiftUI's `GraphicsContext.Filter`: the colour filters a cell's colours can
//  take, and those that need a drawing's pixels.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUIStyling

/// A matrix to use in an RGBA colour transform — mirrors SwiftUI's
/// `ColorMatrix`. Each output channel is its row of four weights times the
/// input's channels, in 0 to 1, plus the row's fifth, a constant.
public struct ColorMatrix: Equatable, Sendable {
    public var r1: Float = 1, r2: Float = 0, r3: Float = 0, r4: Float = 0, r5: Float = 0
    public var g1: Float = 0, g2: Float = 1, g3: Float = 0, g4: Float = 0, g5: Float = 0
    public var b1: Float = 0, b2: Float = 0, b3: Float = 1, b4: Float = 0, b5: Float = 0
    public var a1: Float = 0, a2: Float = 0, a3: Float = 0, a4: Float = 1, a5: Float = 0

    /// The identity matrix.
    public init() {}

    func applied(to colour: CanvasRGBA) -> CanvasRGBA {
        let (r, g, b, a) = (Float(colour.red) / 255, Float(colour.green) / 255, Float(colour.blue) / 255, Float(colour.alpha) / 255)
        func byte(_ value: Float) -> UInt8 { UInt8((min(1, max(0, value)) * 255).rounded()) }
        return CanvasRGBA(
            red: byte(r1 * r + r2 * g + r3 * b + r4 * a + r5),
            green: byte(g1 * r + g2 * g + g3 * b + g4 * a + g5),
            blue: byte(b1 * r + b2 * g + b3 * b + b4 * a + b5),
            alpha: byte(a1 * r + a2 * g + a3 * b + a4 * a + a5))
    }
}

extension GraphicsContext {
    /// A filter — mirrors SwiftUI's `GraphicsContext.Filter`.
    ///
    /// The colour filters apply to a glyph's colours as well as to pixels. The
    /// others need a drawing's pixels, so a glyph is drawn past them as it is: a
    /// cell's glyph cannot be blurred. Not offered, for want of what they act
    /// through: the shaders (`colorShader`, `distortionShader`, `layerShader`),
    /// which run on a GPU, and `projectionTransform`, as TUI has no
    /// `ProjectionTransform`.
    public struct Filter: Sendable {
        enum Kind: Sendable {
            case multiply(Color)
            case hueRotation(Double)
            case saturation(Double)
            case brightness(Double)
            case contrast(Double)
            case invert(Double)
            case grayscale(Double)
            case colorMatrix(ColorMatrix)
            case luminanceToAlpha
            case alphaThreshold(min: Double, max: Double, color: Color)
            case blur(radius: CGFloat, options: BlurOptions)
            case shadow(color: Color, radius: CGFloat, offset: CGPoint, style: (mode: BlendMode, options: ShadowOptions))
        }

        let kind: Kind

        /// Multiplies each colour by `color`, channel by channel.
        public static func colorMultiply(_ color: Color) -> Self { Self(kind: .multiply(color)) }
        /// Turns each colour's hue by `angle`.
        public static func hueRotation(_ angle: Angle) -> Self { Self(kind: .hueRotation(angle.degrees)) }
        /// Keeps `amount` of each colour's saturation (above 1 adds).
        public static func saturation(_ amount: Double) -> Self { Self(kind: .saturation(amount)) }
        /// Adds `amount` of the full range to each channel.
        public static func brightness(_ amount: Double) -> Self { Self(kind: .brightness(amount)) }
        /// Scales each channel's distance from the middle grey by `amount`.
        public static func contrast(_ amount: Double) -> Self { Self(kind: .contrast(amount)) }
        /// Inverts each colour, `amount` of the way.
        public static func colorInvert(_ amount: Double = 1) -> Self { Self(kind: .invert(amount)) }
        /// Takes `amount` of each colour's colour out, toward its grey.
        public static func grayscale(_ amount: Double) -> Self { Self(kind: .grayscale(amount)) }

        /// Sends each pixel through `matrix`.
        public static func colorMatrix(_ matrix: ColorMatrix) -> Self { Self(kind: .colorMatrix(matrix)) }
        /// Makes each pixel's alpha its luminance, and its colour black.
        public static var luminanceToAlpha: Self { Self(kind: .luminanceToAlpha) }
        // SwiftUI's own default colour, for its signature.
        // swiftlint:disable framework_colour_literal
        /// Draws `color` where a pixel's alpha is between `min` and `max`, and
        /// nothing elsewhere.
        public static func alphaThreshold(min: Double, max: Double = 1, color: Color = Color.black) -> Self {
            Self(kind: .alphaThreshold(min: min, max: max, color: color))
        }
        // swiftlint:enable framework_colour_literal
        /// Blurs the drawing by a Gaussian of about `radius`, in the context's units.
        public static func blur(radius: CGFloat, options: BlurOptions = BlurOptions()) -> Self {
            Self(kind: .blur(radius: radius, options: options))
        }
        /// Draws a shadow of the drawing.
        ///
        /// - Parameters:
        ///   - color: The shadow's colour.
        ///   - radius: Its blur, in the context's units.
        ///   - x: Its offset across.
        ///   - y: Its offset down.
        ///   - blendMode: How it lands on what is beneath.
        ///   - options: Where it goes, and what it is cast from.
        public static func shadow(
            color: Color = Color(.sRGB, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0,
            blendMode: BlendMode = .normal, options: ShadowOptions = ShadowOptions()
        ) -> Self {
            Self(kind: .shadow(color: color, radius: radius, offset: CGPoint(x: x, y: y), style: (blendMode, options)))
        }

        /// `color` through this filter; itself where it has no RGB, or where
        /// this filter is not one of colours alone.
        func applied(to color: Color) -> Color {
            switch kind {
            case .multiply(let tint): color.multiplied(by: tint)
            case .hueRotation(let degrees): color.hueRotated(byDegrees: degrees)
            case .saturation(let amount): color.saturated(keeping: amount)
            case .brightness(let amount): color.brightened(by: amount)
            case .contrast(let amount): color.contrasted(by: amount)
            case .invert(let amount): Color.lerp(color, color.inverted, phase: amount)
            case .grayscale(let amount): color.saturated(keeping: 1 - amount)
            case .colorMatrix, .luminanceToAlpha, .alphaThreshold, .blur, .shadow: color
            }
        }

        /// Whether this filter acts on a drawing's pixels, not on each colour
        /// alone.
        var needsPixels: Bool {
            switch kind {
            case .colorMatrix, .luminanceToAlpha, .alphaThreshold, .blur, .shadow: true
            case .multiply, .hueRotation, .saturation, .brightness, .contrast, .invert, .grayscale: false
            }
        }
    }

    /// Options for a filter — mirrors SwiftUI's `GraphicsContext.FilterOptions`.
    /// None changes how a colour is filtered.
    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
    }

    /// Options for a blur — mirrors SwiftUI's `GraphicsContext.BlurOptions`.
    public struct BlurOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Keeps the drawing's alpha, so an edge stays hard.
        public static var opaque: Self { Self(rawValue: 1) }
        /// Asks for the blurred result to be dithered. A hint: a cell or a
        /// picture's pixel holds eight bits a channel either way, and the blur
        /// here has no banding to hide at the sizes a terminal draws.
        public static var dithersResult: Self { Self(rawValue: 2) }
    }

    /// Options for a shadow — mirrors SwiftUI's `GraphicsContext.ShadowOptions`.
    public struct ShadowOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Draws the shadow over the drawing rather than beneath it.
        public static var shadowAbove: Self { Self(rawValue: 1) }
        /// Draws only the shadow.
        public static var shadowOnly: Self { Self(rawValue: 2) }
        /// Casts the shadow from what the drawing leaves empty.
        public static var invertsAlpha: Self { Self(rawValue: 4) }
        /// Casts it per shape rather than from the group. Each draw here is its
        /// own group, so this already holds.
        public static var disablesGroup: Self { Self(rawValue: 8) }
    }

    /// Adds `filter` to what the next draws are drawn through — mirrors
    /// SwiftUI's `addFilter(_:options:)`.
    public mutating func addFilter(_ filter: Filter, options: FilterOptions = FilterOptions()) {
        filters.append(filter)
    }

    // MARK: Filters over pixels

    /// `drawing` through every filter in turn.
    func applyingFilters(to drawing: CanvasRaster) -> CanvasRaster {
        var current = drawing
        for filter in filters { current = applying(filter, to: current) }
        return current
    }

    private func applying(_ filter: Filter, to drawing: CanvasRaster) -> CanvasRaster {
        switch filter.kind {
        case .multiply, .hueRotation, .saturation, .brightness, .contrast, .invert, .grayscale:
            drawing.transformPixels { _, _, colour in
                guard colour.alpha > 0 else { return colour }
                // The drawing's own colour: content, not a framework ink.
                // swiftlint:disable:next framework_colour_literal
                let color = filter.applied(to: Color.rgb(colour.red, colour.green, colour.blue))
                guard let rgb = color.rgbComponents else { return colour }
                return CanvasRGBA(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: colour.alpha)
            }
        case .colorMatrix(let matrix):
            drawing.transformPixels { _, _, colour in matrix.applied(to: colour) }
        case .luminanceToAlpha:
            drawing.transformPixels { _, _, colour in
                let luminance = 0.2126 * Double(colour.red) + 0.7152 * Double(colour.green) + 0.0722 * Double(colour.blue)
                return CanvasRGBA(red: 0, green: 0, blue: 0, alpha: UInt8((luminance * Double(colour.alpha) / 255).rounded()))
            }
        case .alphaThreshold(let low, let high, let color):
            let inked = surface.pixel(of: color)
            drawing.transformPixels { _, _, colour in
                let alpha = Double(colour.alpha) / 255
                return alpha >= low && alpha <= high ? inked : .clear
            }
        case .blur(let radius, let options):
            return drawing.blurred(
                radius: pixelRadius(radius), keepingAlpha: options.contains(.opaque))
        case .shadow(let color, let radius, let offset, let style):
            return shadow(of: drawing, color: color, radius: radius, offset: offset, mode: style.mode, options: style.options)
        }
        return drawing
    }

    /// A length in the context's units, in pixels across and down.
    private func pixelRadius(_ radius: CGFloat) -> (across: Double, down: Double) {
        (
            Double(radius) * Double(surface.grid.across),
            Double(radius) * Double(surface.grid.down) / Double(surface.unitsPerRow)
        )
    }

    private func shadow(
        of drawing: CanvasRaster, color: Color, radius: CGFloat, offset: CGPoint, mode: BlendMode, options: ShadowOptions
    ) -> CanvasRaster {
        let ink = surface.pixel(of: color)
        let invert = options.contains(.invertsAlpha)
        let shift = (
            x: Int((offset.x * CGFloat(surface.grid.across)).rounded()),
            y: Int((offset.y * CGFloat(surface.grid.down) / surface.unitsPerRow).rounded())
        )
        let cast = CanvasRaster(width: drawing.width, height: drawing.height, isLinear: drawing.isLinear)
        cast.transformPixels { x, y, _ in
            let share = Double(drawing[x - shift.x, y - shift.y].alpha) / 255
            return ink.fading(invert ? 1 - share : share)
        }
        let blurred = radius > 0 ? cast.blurred(radius: pixelRadius(radius), keepingAlpha: false) : cast
        guard !options.contains(.shadowOnly) else { return blurred }
        if options.contains(.shadowAbove) {
            let result = CanvasRaster(width: drawing.width, height: drawing.height, isLinear: drawing.isLinear)
            result.paint(layer: drawing, opacity: 1, mode: .normal, clip: nil)
            result.paint(layer: blurred, opacity: 1, mode: mode, clip: nil)
            return result
        }
        // A shadow beneath what cast it is mode-blended only with what it
        // lands on, and the drawing lies over the pair.
        blurred.paint(layer: drawing, opacity: 1, mode: .normal, clip: nil)
        return blurred
    }
}

// MARK: - Blurring

extension CanvasRaster {
    /// These pixels blurred by three box passes, the usual stand-in for a
    /// Gaussian of the radius (its standard deviation), across and then down.
    /// Premultiplied, so a clear pixel's colour does not bleed in.
    func blurred(radius: (across: Double, down: Double), keepingAlpha: Bool) -> CanvasRaster {
        let blurred = CanvasRaster(width: width, height: height, isLinear: isLinear)
        guard width > 0, height > 0 else { return blurred }
        var channels = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let colour = self[x, y]
                let alpha = Float(colour.alpha)
                let index = (y * width + x) * 4
                channels[index] = Float(colour.red) * alpha / 255
                channels[index + 1] = Float(colour.green) * alpha / 255
                channels[index + 2] = Float(colour.blue) * alpha / 255
                channels[index + 3] = alpha
            }
        }
        let across = Self.boxRadius(for: radius.across)
        let down = Self.boxRadius(for: radius.down)
        for _ in 0..<3 {
            if across > 0 { Self.boxPass(&channels, count: height, length: width, stride: 4, line: width * 4, radius: across) }
            if down > 0 { Self.boxPass(&channels, count: width, length: height, stride: width * 4, line: 4, radius: down) }
        }
        blurred.transformPixels { x, y, _ in
            let index = (y * width + x) * 4
            let alpha = channels[index + 3]
            guard alpha > 0 else { return keepingAlpha ? self[x, y] : .clear }
            func byte(_ value: Float) -> UInt8 { UInt8(min(255, max(0, (value * 255 / alpha).rounded()))) }
            return CanvasRGBA(
                red: byte(channels[index]), green: byte(channels[index + 1]), blue: byte(channels[index + 2]),
                alpha: keepingAlpha ? self[x, y].alpha : UInt8(min(255, alpha.rounded())))
        }
        return blurred
    }

    /// The half-width of the box whose three passes approximate a Gaussian of
    /// standard deviation `sigma`.
    private static func boxRadius(for sigma: Double) -> Int {
        guard sigma.isFinite, sigma > 0 else { return 0 }
        return Int(min(1024, (sigma * 3 * (2 * Double.pi).squareRoot() / 4 + 0.5) / 2))
    }

    /// One sliding-window pass over `count` lines of `length` pixels: pixels of
    /// a line lie `stride` apart, and lines `line` apart. What lies past an end
    /// is clear, so a drawing's edge fades.
    private static func boxPass(
        _ channels: inout [Float], count: Int, length: Int, stride: Int, line: Int, radius: Int
    ) {
        let weight = 1 / Float(radius * 2 + 1)
        var scratch = [Float](repeating: 0, count: length)
        for lineIndex in 0..<count {
            for channel in 0..<4 {
                let base = lineIndex * line + channel
                var sum: Float = 0
                for offset in 0...min(radius, length - 1) { sum += channels[base + offset * stride] }
                for position in 0..<length {
                    scratch[position] = sum * weight
                    let leaving = position - radius
                    let entering = position + radius + 1
                    if leaving >= 0 { sum -= channels[base + leaving * stride] }
                    if entering < length { sum += channels[base + entering * stride] }
                }
                for position in 0..<length { channels[base + position * stride] = scratch[position] }
            }
        }
    }
}
