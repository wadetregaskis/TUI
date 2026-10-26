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
    /// - Parameters:
    ///   - mode: How the two combine.
    ///   - opacity: How much of the blend lands, `0` through `1`.
    ///   - backdrop: The colour behind.
    /// - Returns: The result, opaque.
    package func blending(_ mode: BlendMode, at opacity: Double, over backdrop: Color) -> Self {
        guard mode != .normal, let source = rgbComponents, let backdropRGB = backdrop.rgbComponents,
            let blended = mode.blended(Self.channels(source), over: Self.channels(backdropRGB))
        else { return self.opacity(opacity, over: backdrop) }
        // This colour's own alpha is coverage too, as `opacity(_:over:)` reads it.
        let coverage = Double(alpha) / 255 * min(1, max(0, opacity))
        let behind = Self.channels(backdropRGB)
        // Mixed before clamping, as macOS does (``BlendMode/blended(_:over:)``).
        func byte(_ blend: Double, _ under: Double) -> UInt8 {
            UInt8((min(1, max(0, under + (blend - under) * coverage)) * 255).rounded())
        }
        // Arithmetic, not ink a control picks: the blend's answer.
        // swiftlint:disable:next framework_colour_literal
        return Self.rgb(
            byte(blended.red, behind.red), byte(blended.green, behind.green), byte(blended.blue, behind.blue))
    }

    private static func channels(_ rgb: (red: UInt8, green: UInt8, blue: UInt8)) -> BlendMode.Channels {
        (Double(rgb.red) / 255, Double(rgb.green) / 255, Double(rgb.blue) / 255)
    }
}
