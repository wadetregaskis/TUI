//  🖥️ TUI — A Terminal UI framework for Swift
//  BlendMode.swift
//
//  How a layer's colours combine with what is behind it — SwiftUI's BlendMode,
//  and the arithmetic each mode does to a cell's colours.
//
//  Created by Wade Tregaskis
//  License: MIT

/// How a view's colours combine with the colours behind it. Matches SwiftUI's
/// `BlendMode`.
///
/// A cell has two colours, its ink and its field, and a mode works on each with
/// its own counterpart behind it, as ``View/opacity(_:)`` does: the ink against
/// what is behind the glyph, the field against the field. The arithmetic is
/// SwiftUI's on macOS, measured (`Tools/SwiftUIProbes/Blend modes`): on the
/// colours' encoded sRGB values, not linear light, with the W3C compositing
/// specification's formulas, except ``softLight``, which macOS draws with the
/// simpler `(1 − 2s)·b² + 2s·b`. A translucent view mixes the blended colour
/// with what is behind it by its opacity: `(1 − α)·b + α·B(b, s)`.
///
/// The glyph is a decision, as under ``View/opacity(_:)``: a cell holds one
/// character, so where both sides draw one the view's is drawn at or above
/// half opacity, and the colour it is drawn in is the blended one. Where the
/// view draws no glyph over text, the text keeps its character and both its
/// colours blend: a ``multiply`` highlight over a line tints the letters with
/// it, as it tints the pixels of SwiftUI's.
///
/// The last five modes are not colour arithmetic, they decide which side shows
/// (Porter and Duff's operators): ``sourceAtop`` draws the view only over what
/// is behind it, ``destinationOver`` draws what is behind over the view,
/// ``destinationOut`` erases what is behind where the view draws, and
/// ``plusDarker`` and ``plusLighter`` add the two.
public enum BlendMode: Sendable, Hashable, CaseIterable {
    /// The view's colours, over what is behind them.
    case normal
    /// Each channel the product of the two: never lighter than either.
    case multiply
    /// The inverse of multiplying the inverses: never darker than either.
    case screen
    /// ``multiply`` or ``screen``, by what is behind: its contrast kept.
    case overlay
    /// Each channel the darker of the two.
    case darken
    /// Each channel the lighter of the two.
    case lighten
    /// What is behind, brightened by the view.
    case colorDodge
    /// What is behind, darkened by the view.
    case colorBurn
    /// ``overlay``, softened.
    case softLight
    /// ``multiply`` or ``screen``, by the view: ``overlay`` with the two swapped.
    case hardLight
    /// Each channel the difference of the two.
    case difference
    /// ``difference`` with lower contrast.
    case exclusion
    /// The view's hue, with the saturation and luminosity behind it.
    case hue
    /// The view's saturation, with the hue and luminosity behind it.
    case saturation
    /// The view's hue and saturation, with the luminosity behind it.
    case color
    /// The view's luminosity, with the hue and saturation behind it.
    case luminosity
    /// The view, drawn only where something is behind it.
    case sourceAtop
    /// What is behind, drawn over the view.
    case destinationOver
    /// What is behind, erased where the view draws.
    case destinationOut
    /// The two added, less one: darker than either.
    case plusDarker
    /// The two added: lighter than either.
    case plusLighter
}

extension BlendMode {
    /// One colour, as three encoded sRGB channels from 0 through 1.
    package typealias Channels = (red: Double, green: Double, blue: Double)

    /// Whether this mode is colour arithmetic, which ``blended(_:over:)``
    /// answers, rather than one of the operators that decide which side shows.
    package var isArithmetic: Bool {
        switch self {
        case .sourceAtop, .destinationOver, .destinationOut: false
        default: true
        }
    }

    /// `source` blended over `backdrop` at full opacity, or `nil` for a mode
    /// that is not arithmetic (``isArithmetic``).
    ///
    /// NOT clamped to 0…1: ``colorDodge`` and ``plusLighter`` overshoot, and macOS
    /// mixes a translucent source's alpha in before it clamps — half a dodge that
    /// would reach 1.29 lands at 1, not at the half of 1 a clamped value gives
    /// (`Tools/SwiftUIProbes/Blend modes`). The caller clamps after mixing.
    package func blended(_ source: Channels, over backdrop: Channels) -> Channels? {
        switch self {
        case .normal: return source
        case .hue: return Self.setLum(Self.setSat(source, Self.sat(backdrop)), Self.lum(backdrop))
        case .saturation: return Self.setLum(Self.setSat(backdrop, Self.sat(source)), Self.lum(backdrop))
        case .color: return Self.setLum(source, Self.lum(backdrop))
        case .luminosity: return Self.setLum(backdrop, Self.lum(source))
        case .sourceAtop, .destinationOver, .destinationOut: return nil
        default:
            return (
                separable(source.red, backdrop.red), separable(source.green, backdrop.green),
                separable(source.blue, backdrop.blue))
        }
    }

    /// A separable mode on one channel: `s` the view's, `b` what is behind.
    private func separable(_ s: Double, _ b: Double) -> Double {
        switch self {
        case .multiply: return s * b
        case .screen: return s + b - s * b
        case .overlay: return Self.hardLight(b, over: s)
        case .darken: return min(s, b)
        case .lighten: return max(s, b)
        case .colorDodge: return Self.dodge(s, b)
        case .colorBurn: return Self.burn(s, b)
        // macOS's soft light, measured: not the W3C curve, which gives 89 where
        // macOS draws 75 for 0.8 over 0.2 (`Tools/SwiftUIProbes/Blend modes`).
        case .softLight: return (1 - 2 * s) * b * b + 2 * s * b
        case .hardLight: return Self.hardLight(s, over: b)
        case .difference: return abs(s - b)
        case .exclusion: return s + b - 2 * s * b
        case .plusDarker: return max(0, s + b - 1)
        case .plusLighter: return s + b
        default: return s
        }
    }

    private static func dodge(_ s: Double, _ b: Double) -> Double {
        if b <= 0 { return 0 }
        return s >= 1 ? 1 : b / (1 - s)
    }

    private static func burn(_ s: Double, _ b: Double) -> Double {
        if b >= 1 { return 1 }
        return s <= 0 ? 0 : 1 - min(1, (1 - b) / s)
    }

    private static func hardLight(_ s: Double, over b: Double) -> Double {
        s <= 0.5 ? b * 2 * s : b + (2 * s - 1) - b * (2 * s - 1)
    }

    // The non-separable modes' helpers, the W3C specification's.

    private static func lum(_ c: Channels) -> Double {
        0.3 * c.red + 0.59 * c.green + 0.11 * c.blue
    }

    private static func clipColor(_ c: Channels) -> Channels {
        let luminosity = lum(c)
        let n = min(c.red, c.green, c.blue)
        let x = max(c.red, c.green, c.blue)
        var result = c
        if n < 0 {
            let scale = luminosity / (luminosity - n)
            result = (
                luminosity + (result.red - luminosity) * scale, luminosity + (result.green - luminosity) * scale,
                luminosity + (result.blue - luminosity) * scale)
        }
        if x > 1 {
            let scale = (1 - luminosity) / (x - luminosity)
            result = (
                luminosity + (result.red - luminosity) * scale, luminosity + (result.green - luminosity) * scale,
                luminosity + (result.blue - luminosity) * scale)
        }
        return result
    }

    private static func setLum(_ c: Channels, _ luminosity: Double) -> Channels {
        let d = luminosity - lum(c)
        return clipColor((c.red + d, c.green + d, c.blue + d))
    }

    private static func sat(_ c: Channels) -> Double {
        max(c.red, c.green, c.blue) - min(c.red, c.green, c.blue)
    }

    /// `c` with its saturation `s`: its largest channel at `s`, its smallest at
    /// 0, the middle one in proportion between them.
    private static func setSat(_ c: Channels, _ s: Double) -> Channels {
        let values = [c.red, c.green, c.blue]
        let maxIndex = values.firstIndex(of: values.max() ?? 0) ?? 0
        let minIndex = values.lastIndex(of: values.min() ?? 0) ?? 0
        guard maxIndex != minIndex, values[maxIndex] > values[minIndex] else { return (0, 0, 0) }
        let midIndex = 3 - maxIndex - minIndex
        var out = [0.0, 0.0, 0.0]
        out[midIndex] = (values[midIndex] - values[minIndex]) * s / (values[maxIndex] - values[minIndex])
        out[maxIndex] = s
        return (out[0], out[1], out[2])
    }
}
