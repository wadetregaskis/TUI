//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageTransform+Recolour.swift
//
//  A colour effect applied to the pixels of a picture's derived copy, as the
//  effect recolours cells (`SGRColorRewrite+Pictures.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIStyling

extension ImageTransform {
    /// A colour effect, as `.brightness(_:)`, `.hueRotation(_:)` and their
    /// kin recolour a cell (`Color+ColorSpaces.swift`), applied to each pixel
    /// of a picture the effect is over.
    ///
    /// Its amount is quantised, as a mix's is, so an effect that animates asks
    /// for a copy per step rather than one a frame.
    package enum Recolour: Hashable, Sendable {
        /// `Color.brightened(by:)`, in 64ths.
        case brightness(Int16)
        /// `Color.contrasted(by:)`, in 64ths.
        case contrast(Int16)
        /// `Color.saturated(keeping:)`, in 64ths.
        case saturation(Int16)
        /// `Color.hueRotated(byDegrees:)`, in whole degrees.
        case hueRotation(Int16)
        /// `Color.inverted`.
        case invert
        /// `Color.multiplied(by:)`, by 0xRRGGBB.
        case multiply(UInt32)

        /// An amount in 64ths, as the cases above keep it, held to what fits:
        /// a modifier's amount is the caller's, and can be anything.
        package static func sixtyFourths(_ amount: Double) -> Int16 {
            let scaled = (amount * 64).rounded()
            guard !scaled.isNaN else { return 0 }
            return Int16(max(Double(Int16.min), min(Double(Int16.max), scaled)))
        }

        /// A turn in whole degrees, less than a full turn either way.
        package static func degrees(_ amount: Double) -> Int16 {
            let turned = amount.truncatingRemainder(dividingBy: 360).rounded()
            return turned.isFinite ? Int16(turned) : 0
        }

        /// `color` recoloured.
        func applied(to color: Color) -> Color {
            switch self {
            case .brightness(let amount): return color.brightened(by: Double(amount) / 64)
            case .contrast(let amount): return color.contrasted(by: Double(amount) / 64)
            case .saturation(let amount): return color.saturated(keeping: Double(amount) / 64)
            case .hueRotation(let degrees): return color.hueRotated(byDegrees: Double(degrees))
            case .invert: return color.inverted
            case .multiply(let tint):
                // The tint the effect names, unpacked: arithmetic, not ink.
                // swiftlint:disable:next framework_colour_literal
                let unpacked = Color.rgb(UInt8((tint >> 16) & 0xFF), UInt8((tint >> 8) & 0xFF), UInt8(tint & 0xFF))
                return color.multiplied(by: unpacked)
            }
        }
    }
}
