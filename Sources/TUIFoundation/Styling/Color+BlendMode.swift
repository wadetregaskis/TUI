//  🖥️ TUI — A Terminal UI framework for Swift
//  Color+BlendMode.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

extension Color {
    /// This colour combined with `backdrop` by `mode`, then composited over it at
    /// `opacity`: `(1 − α)·b + α·B(b, s)`, on the encoded sRGB values, as macOS
    /// draws a blend mode (`Tools/SwiftUIProbes/Blend modes`).
    ///
    /// ``BlendMode/normal``, a mode that is not colour arithmetic, or a side with no
    /// RGB (``Color/default``, or the terminal's own colours before they are
    /// reported) is ``opacity(_:over:)``: there is nothing to combine, and the
    /// colours keep their spelling where the mix leaves them whole.
    ///
    /// With `linearLight`, as inside a `drawingGroup(colorMode: .linear)`, the
    /// channels are decoded to linear light first, combined and mixed there, and
    /// encoded again.
    ///
    /// - Parameters:
    ///   - mode: How the two combine.
    ///   - opacity: How much of the blend lands, `0` through `1`.
    ///   - backdrop: The colour behind.
    ///   - linearLight: Whether to combine in linear light.
    /// - Returns: The result, opaque.
    package func blending(
        _ mode: BlendMode, at opacity: Double, over backdrop: Color, linearLight: Bool = false
    ) -> Self {
        // This colour's own alpha is coverage too, as `opacity(_:over:)` reads it.
        let coverage = Double(alpha) / 255 * min(1, max(0, opacity))
        guard mode != .normal, let source = rgbComponents, let backdropRGB = backdrop.rgbComponents,
            let blended = mode.blended(
                Self.channels(source, linearLight: linearLight), over: Self.channels(backdropRGB, linearLight: linearLight))
        else {
            return linearLight ? compositing(coverage, over: backdrop) : self.opacity(opacity, over: backdrop)
        }
        let behind = Self.channels(backdropRGB, linearLight: linearLight)
        // Mixed before clamping, as macOS does (``BlendMode/blended(_:over:)``).
        func byte(_ blend: Double, _ under: Double) -> UInt8 {
            let mixed = under + (blend - under) * coverage
            return linearLight ? Self.encodedChannel(mixed) : UInt8((min(1, max(0, mixed)) * 255).rounded())
        }
        // Arithmetic, not ink a control picks: the blend's answer.
        // swiftlint:disable:next framework_colour_literal
        return Self.rgb(
            byte(blended.red, behind.red), byte(blended.green, behind.green), byte(blended.blue, behind.blue))
    }

    private static func channels(_ rgb: (red: UInt8, green: UInt8, blue: UInt8), linearLight: Bool) -> BlendMode.Channels {
        guard linearLight else { return (Double(rgb.red) / 255, Double(rgb.green) / 255, Double(rgb.blue) / 255) }
        return (linearChannel(rgb.red), linearChannel(rgb.green), linearChannel(rgb.blue))
    }
}
