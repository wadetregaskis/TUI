//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext+Shading.swift
//
//  SwiftUI's `GraphicsContext.Shading`: what a path is painted with, and how
//  each kind is asked for its colour at a pixel.
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
    /// Options for a gradient shading — mirrors SwiftUI's
    /// `GraphicsContext.GradientOptions`.
    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Repeats the ramp past its ends.
        public static var `repeat`: Self { Self(rawValue: 1) }
        /// Repeats the ramp past its ends, every other time backwards.
        public static var mirror: Self { Self(rawValue: 2) }
        /// Interpolates between the stops in linear light.
        public static var linearColor: Self { Self(rawValue: 4) }
    }

    /// The colour or pattern a path is painted with — mirrors SwiftUI's
    /// `GraphicsContext.Shading`. Not offered: `shader`, which runs on a GPU.
    public struct Shading: Sendable {
        enum Kind: Sendable {
            case backdrop
            case foreground
            case palette([Shading])
            case color(Color)
            case style(any ShapeStyle)
            case paint(Paint)
            case linear(Gradient, start: CGPoint, end: CGPoint, options: GradientOptions)
            case radial(Gradient, center: CGPoint, radii: (start: CGFloat, end: CGFloat), options: GradientOptions)
            case conic(Gradient, center: CGPoint, angle: Angle, options: GradientOptions)
            case tiled(Image, origin: CGPoint, sourceRect: CGRect, scale: CGFloat)
        }

        let kind: Kind

        /// What the context has drawn so far, as it stands when this paints.
        public static var backdrop: Self { Self(kind: .backdrop) }
        /// The view's foreground style.
        public static var foreground: Self { Self(kind: .foreground) }
        /// Several shadings, for a drawing with layers of its own. A path has
        /// one layer, and paints with the first.
        public static func palette(_ array: [Self]) -> Self { Self(kind: .palette(array)) }
        /// A colour.
        public static func color(_ color: Color) -> Self { Self(kind: .color(color)) }
        /// A colour from its channels.
        public static func color(
            _ colorSpace: Color.RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1
        ) -> Self {
            Self(kind: .color(Color(colorSpace, red: red, green: green, blue: blue, opacity: opacity)))
        }
        /// A colour from its grey.
        public static func color(_ colorSpace: Color.RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) -> Self {
            Self(kind: .color(Color(colorSpace, white: white, opacity: opacity)))
        }
        /// A shape style. A gradient's unit points are in the box of the path
        /// it paints.
        public static func style<S: ShapeStyle>(_ style: S) -> Self { Self(kind: .style(style)) }
        /// A ramp along the line between two points, in the context's coordinates.
        public static func linearGradient(
            _ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = GradientOptions()
        ) -> Self {
            Self(kind: .linear(gradient, start: startPoint, end: endPoint, options: options))
        }
        /// A ramp outward from `center`, between two radii.
        public static func radialGradient(
            _ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat,
            options: GradientOptions = GradientOptions()
        ) -> Self {
            Self(kind: .radial(gradient, center: center, radii: (startRadius, endRadius), options: options))
        }
        /// A ramp round `center`, from `angle` once clockwise.
        public static func conicGradient(
            _ gradient: Gradient, center: CGPoint, angle: Angle = Angle(), options: GradientOptions = GradientOptions()
        ) -> Self {
            Self(kind: .conic(gradient, center: center, angle: angle, options: options))
        }
        /// A mesh of colours over the box of the path it paints.
        public static func meshGradient(_ mesh: MeshGradient) -> Self { Self(kind: .style(mesh)) }
        /// An image repeated, starting from `origin`.
        ///
        /// - Parameters:
        ///   - image: The image.
        ///   - origin: Where a tile starts, in the context's coordinates.
        ///   - sourceRect: The region drawn, in the image's unit space.
        ///   - scale: A scale factor applied to the image.
        public static func tiledImage(
            _ image: Image, origin: CGPoint = .zero, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
            scale: CGFloat = 1
        ) -> Self {
            Self(kind: .tiled(image, origin: origin, sourceRect: sourceRect, scale: scale))
        }
    }

    /// `shading` with what it takes from the environment taken now, so it can
    /// be used in a context whose environment differs — mirrors SwiftUI's
    /// `resolve(_:)`.
    public func resolve(_ shading: Shading) -> Shading {
        switch shading.kind {
        case .foreground: Shading(kind: .paint(environment.foregroundStyle ?? .color(environment.palette.foreground)))
        case .style(let style): Shading(kind: .paint(style.paint(in: environment)))
        case .color(let color): Shading(kind: .color(color.resolve(with: environment.palette)))
        case .palette(let array): Shading(kind: .palette(array.map(resolve)))
        case .backdrop, .paint, .linear, .radial, .conic, .tiled: shading
        }
    }

    // MARK: A shading's colour at a pixel

    /// What `shading` paints, for a path with user-space box `bounds`.
    func source(of shading: Shading, bounds: CGRect) -> CanvasSource {
        switch shading.kind {
        case .backdrop:
            let copy = target.bytes
            let width = target.width
            return .sampled { x, y in
                let index = (y * width + x) * 4
                return CanvasRGBA(red: copy[index], green: copy[index + 1], blue: copy[index + 2], alpha: copy[index + 3])
            }
        case .palette(let array):
            guard let first = array.first else { return .flat(.clear) }
            return source(of: first, bounds: bounds)
        case .color(let color):
            return .flat(surface.pixel(of: color))
        case .foreground, .style:
            return source(of: resolve(shading), bounds: bounds)
        case .paint(let paint):
            return source(of: paint, bounds: bounds)
        case .linear(let gradient, let start, let end, let options):
            let (dx, dy) = (end.x - start.x, end.y - start.y)
            let length = dx * dx + dy * dy
            return gradientSource(gradient, options: options) { point in
                length > 0 ? Double(((point.x - start.x) * dx + (point.y - start.y) * dy) / length) : 0
            }
        case .radial(let gradient, let center, let radii, let options):
            let (startRadius, span) = (radii.start, radii.end - radii.start)
            return gradientSource(gradient, options: options) { point in
                let distance = hypot(point.x - center.x, point.y - center.y)
                return span != 0 ? Double((distance - startRadius) / span) : 0
            }
        case .conic(let gradient, let center, let angle, let options):
            return gradientSource(gradient, options: options) { point in
                let bearing: Double = atan2(Double(point.y - center.y), Double(point.x - center.x))
                let turn: Double = (bearing - angle.radians) / (2 * Double.pi)
                return turn - turn.rounded(.down)
            }
        case .tiled(let image, let origin, let sourceRect, let scale):
            return tiledSource(image, origin: origin, sourceRect: sourceRect, scale: scale)
        }
    }

    /// What a resolved paint paints: a colour; a ramp through ``RampSampler``,
    /// as a shape or a picture of a ramp is, over the path's box in pixels; or
    /// an image, tiled.
    private func source(of paint: Paint, bounds: CGRect) -> CanvasSource {
        switch paint {
        case .color(let color): return .flat(surface.pixel(of: color))
        case .shadowed(let base, _), .blended(let base, _), .frosted(let base, _): return source(of: base, bounds: bounds)
        case .image(let image): return tiledSource(image)
        case .gradient, .mesh: break
        }
        let grid = surface.grid
        let box = bounds.applying(surface.deviceMatrix).applying(transform)
        guard box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite else { return .flat(.clear) }
        // A frame's cell is a pixel here; the sampler is told how tall it is.
        let limit = CGFloat(1 << 20)
        let frame = GradientFrame(
            originX: 0, originY: 0, width: Int(min(limit, max(1, box.width.rounded(.up)))),
            height: Int(min(limit, max(1, box.height.rounded(.up)))))
        let aspect = Double(surface.unitsPerRow) * Double(grid.across) / Double(grid.down)
        guard
            let sampler = RampSampler(
                paint: GradientRaster.inPixels(paint, cellPixels: TerminalCellPixels(width: grid.across, height: grid.down)),
                extent: frame, depth: .truecolor, cellAspect: aspect)
        else { return .flat(surface.pixel(of: paint.representative)) }
        let (originX, originY) = (Int(max(-limit, min(limit, box.minX.rounded(.down)))), Int(max(-limit, min(limit, box.minY.rounded(.down)))))
        let surface = surface
        return .sampled { x, y in
            let entry = sampler.entry(column: x - originX, rowTerm: sampler.rowTerm(y - originY))
            return surface.pixel(of: sampler.ramp[entry])
        }
    }

    /// A ramp whose phase at a pixel `phase` says from the point in the
    /// context's coordinates.
    private func gradientSource(
        _ gradient: Gradient, options: GradientOptions, phase: @escaping (CGPoint) -> Double
    ) -> CanvasSource {
        let table = rampTable(gradient, linear: options.contains(.linearColor))
        let inverse = transform.concatenating(surface.deviceMatrix).inverted()
        let (mirrors, repeats) = (options.contains(.mirror), options.contains(.repeat))
        let lastStep = Double(table.count - 1)
        return .sampled { (x: Int, y: Int) -> CanvasRGBA in
            let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5).applying(inverse)
            var t: Double = phase(point)
            guard t.isFinite else { return table[0] }
            if mirrors {
                let half: Double = t / 2
                let wrapped: Double = half - half.rounded(.down)
                t = wrapped < 0.5 ? wrapped * 2 : 2 - wrapped * 2
            } else if repeats {
                t -= t.rounded(.down)
            }
            let clamped: Double = min(1, max(0, t))
            return table[Int(clamped * lastStep)]
        }
    }

    /// The ramp at evenly spaced phases: the stops' colours as pixels once, not
    /// once a pixel. As many as a channel has steps.
    private func rampTable(_ gradient: Gradient, linear: Bool) -> [CanvasRGBA] {
        let steps = 256
        return (0..<steps).map { step in
            let phase = Double(step) / Double(steps - 1)
            guard linear else { return surface.pixel(of: gradient.color(at: phase)) }
            return linearSample(gradient, at: phase)
        }
    }

    /// The ramp at `phase`, mixed in linear light between the stops either side.
    private func linearSample(_ gradient: Gradient, at phase: Double) -> CanvasRGBA {
        let stops = gradient.ordered
        guard let first = stops.first else { return .clear }
        guard phase > first.location else { return surface.pixel(of: first.color) }
        guard let after = stops.firstIndex(where: { $0.location >= phase }), after > 0 else {
            return surface.pixel(of: stops[stops.count - 1].color)
        }
        let (a, b) = (surface.pixel(of: stops[after - 1].color), surface.pixel(of: stops[after].color))
        let span = stops[after].location - stops[after - 1].location
        let t = span > 0 ? (phase - stops[after - 1].location) / span : 1
        func decode(_ channel: UInt8) -> Double {
            let encoded = Double(channel) / 255
            return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 {
            let value = decode(x) + (decode(y) - decode(x)) * t
            let encoded = value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
            return UInt8((min(1, max(0, encoded)) * 255).rounded())
        }
        return CanvasRGBA(
            red: mix(a.red, b.red), green: mix(a.green, b.green), blue: mix(a.blue, b.blue),
            alpha: UInt8((Double(a.alpha) + (Double(b.alpha) - Double(a.alpha)) * t).rounded()))
    }
}
