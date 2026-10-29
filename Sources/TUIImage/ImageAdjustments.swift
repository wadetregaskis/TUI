//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageAdjustments.swift
//
//  A photo editor's basic adjustments — exposure, black point, highlights,
//  contrast — applied to a picture before anything is read off it (the owner,
//  2026-10-28, afternoon list #29: explicit, orthogonal adjustments rather
//  than a threshold's hidden black level).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// Adjustments to a picture's tones, each channel alike, before a tone curve
/// recolours it and before any character, threshold or palette reads it.
///
/// ```swift
/// Image("tux").imageAdjustments(ImageAdjustments(exposure: 0.5, blackPoint: 0.1))
/// ```
///
/// Each says one thing a person would reach for in a photo editor, and each
/// leaves the picture alone at its default, so they compose in any mix: the
/// picture is brightened by ``exposure``, its shadows below ``blackPoint``
/// sent to black, its top half spread or squeezed by ``highlights``, and then
/// pushed apart or drawn together about mid-grey by ``contrast``, in that
/// order. Not an ``ASCIIToneCurve``, which says what tones BECOME — a duotone,
/// a negative — and comes after these, so the two can be had together.
public struct ImageAdjustments: Sendable, Hashable {
    /// Brightness in photographic stops: `+1` doubles every channel's light,
    /// `-1` halves it. `0` changes nothing.
    public var exposure: Double

    /// The level, `0...1`, at and below which a channel is black, the rest
    /// spread over the whole range: the black level. `0` changes nothing.
    public var blackPoint: Double

    /// How the top half of the range is spread, `-1...1`: below `0` the
    /// highlights are drawn together (detail recovered from near-white), above
    /// it pushed apart. `0` changes nothing.
    public var highlights: Double

    /// How far tones are pushed from mid-grey, `-1...1`: `-1` flattens every
    /// tone to grey, `1` doubles each one's distance from it. `0` changes
    /// nothing.
    public var contrast: Double

    /// Adjustments that change nothing unless given.
    public init(exposure: Double = 0, blackPoint: Double = 0, highlights: Double = 0, contrast: Double = 0) {
        self.exposure = exposure
        self.blackPoint = min(0.99, max(0, blackPoint))
        self.highlights = min(1, max(-1, highlights))
        self.contrast = min(1, max(-1, contrast))
    }

    /// Adjustments that change nothing.
    public static let none = Self()

    /// Whether these change nothing.
    public var isIdentity: Bool { self == .none }

    /// The adjusted value of a channel `value`, `0...1`.
    func adjusted(_ value: Double) -> Double {
        var tone = value * pow(2, exposure)
        tone = max(0, (tone - blackPoint) / (1 - blackPoint))
        if tone > 0.5 { tone = 0.5 + (tone - 0.5) * (1 + highlights) }
        tone = 0.5 + (tone - 0.5) * (1 + contrast)
        return min(1, max(0, tone))
    }

    /// Each channel byte's adjusted byte: worked out once a picture, so the
    /// pixels pay a lookup each.
    func table() -> [UInt8] {
        (0..<256).map { UInt8((adjusted(Double($0) / 255) * 255).rounded()) }
    }

    /// `image` with every pixel's channels adjusted, its alpha kept.
    func apply(to image: inout RGBAImage) {
        guard !isIdentity else { return }
        let table = table()
        image.mapPixels { pixel in
            RGBA(r: table[Int(pixel.r)], g: table[Int(pixel.g)], b: table[Int(pixel.b)], a: pixel.a)
        }
    }
}
