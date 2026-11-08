//  🖥️ TUI — A Terminal UI framework for Swift
//  Color+OKLab.swift
//
//  OKLab and OKLCh, public: constructors and inverses in the shape of
//  `Color+ColorSpaces.swift`'s HSL, HSB and CMYK, and a perceptual difference.
//  TUI-specific: SwiftUI's `Color` has none of these.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - OKLab

extension Color {
    /// Creates a color from OKLab coordinates.
    ///
    /// OKLab (Björn Ottosson, 2020) is a perceptual colour space: equal steps in
    /// it look like equal steps of colour, which is what makes it the space to
    /// build even ramps, shades and gradients in. TUI's own gradients and its
    /// truecolour-to-256 mapping work in it. The numbers are those of CSS's
    /// `oklab()` in its numeric form, so `oklab(0.628 0.225 0.126)` is
    /// `Color.oklab(0.628, 0.225, 0.126)`.
    ///
    /// A point outside what sRGB can show, which most of the space is, has each
    /// channel clamped into range: a terminal has no wider gamut to show it in.
    ///
    /// - Parameters:
    ///   - lightness: The lightness `L`, from 0 (black) to 1 (white).
    ///   - a: The green–red axis: negative is green, positive is red. sRGB
    ///     colours lie between about −0.24 and 0.28.
    ///   - b: The blue–yellow axis: negative is blue, positive is yellow. sRGB
    ///     colours lie between about −0.32 and 0.2.
    /// - Returns: The corresponding RGB color.
    public static func oklab(_ lightness: Double, _ a: Double, _ b: Double) -> Self {
        let rgb = fromOKLab(l: lightness, a: a, b: b)
        return .rgb(rgb.red, rgb.green, rgb.blue)
    }

    /// Converts RGB components to OKLab: lightness 0–1, and the `a` and `b`
    /// axes, each about −0.4 to 0.4 (see ``oklab(_:_:_:)``).
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (lightness, a, b).
    public static func rgbToOKLab(red: UInt8, green: UInt8, blue: UInt8) -> (lightness: Double, a: Double, b: Double) {
        let lab = oklab(red: red, green: green, blue: blue)
        return (lightness: lab.l, a: lab.a, b: lab.b)
    }

    // MARK: - OKLCh

    /// Creates a color from OKLCh coordinates: OKLab in polar form.
    ///
    /// The same space as ``oklab(_:_:_:)``, described by how colourful a colour
    /// is (chroma) and which colour it is (hue) rather than by two axes. Turning
    /// the hue at a fixed lightness and chroma keeps a colour's perceived
    /// lightness, which HSL's hue does not: `hsl(60, 100, 50)` and
    /// `hsl(240, 100, 50)` are yellow and blue, and look nothing like the same
    /// lightness. The numbers are those of CSS's `oklch()` in its numeric form.
    ///
    /// A point outside what sRGB can show has each channel clamped into range,
    /// so a high chroma at a hue sRGB cannot reach comes out duller, and its
    /// hue can shift.
    ///
    /// - Parameters:
    ///   - lightness: The lightness `L`, from 0 (black) to 1 (white).
    ///   - chroma: How colourful, from 0 (grey). sRGB's most colourful, its
    ///     magenta, is about 0.32.
    ///   - hue: The hue angle in degrees (0–360); any other value is taken on
    ///     the circle. Red is about 29, yellow 110, green 142, blue 264.
    /// - Returns: The corresponding RGB color.
    public static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double) -> Self {
        let radians = hue * Double.pi / 180
        return oklab(lightness, chroma * cos(radians), chroma * sin(radians))
    }

    /// Converts RGB components to OKLCh: lightness 0–1, chroma from 0, and hue
    /// 0–360 degrees (see ``oklch(_:_:_:)``).
    ///
    /// A grey has no hue, and reports 0, as ``rgbToHSL(red:green:blue:)``
    /// reports one. A colour within a hair of grey (chroma under 0.0001, below
    /// what a byte can tell apart) counts as grey: its angle is rounding noise.
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (lightness, chroma, hue).
    public static func rgbToOKLCh(
        red: UInt8, green: UInt8, blue: UInt8
    ) -> (lightness: Double, chroma: Double, hue: Double) {
        let lab = oklab(red: red, green: green, blue: blue)
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        guard chroma >= 0.0001 else { return (lightness: lab.l, chroma: chroma, hue: 0) }
        var hue = atan2(lab.b, lab.a) * 180 / Double.pi
        if hue < 0 { hue += 360 }
        return (lightness: lab.l, chroma: chroma, hue: hue)
    }
}

// MARK: - Perceptual Difference

extension Color {
    /// A formula for how different two colours look: ``deltaE(_:method:)``.
    public enum DeltaEMethod: Sendable, Equatable {
        /// ΔEOK: the straight-line distance in OKLab, as CSS Color 4's
        /// `deltaEOK` defines it. 0 is the same colour, 1 is black from white,
        /// and about 0.02 is the least difference most people can see.
        case ok
    }

    /// How different this colour looks from `other`: 0 when they are the same,
    /// and more the further apart they look.
    ///
    /// For the question a contrast ratio can't answer: whether two colours can
    /// be told apart at all, such as two series in a chart. A contrast ratio
    /// (``contrastRatio(against:)``) measures lightness alone, so red and green
    /// of one lightness score 1, and is the measure for text on a background.
    ///
    /// ```swift
    /// if series.color.deltaE(other.color)! < 0.1 {
    ///     // Too close to tell apart at a glance.
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - other: The colour to compare with.
    ///   - method: The formula. ``DeltaEMethod/ok``, the only one, is the default.
    /// - Returns: The difference, or `nil` when either colour has no RGB
    ///   components to measure (``rgbComponents``), such as an unresolved
    ///   semantic colour or a terminal slot the terminal has not reported.
    public func deltaE(_ other: Color, method: DeltaEMethod = .ok) -> Double? {
        guard let mine = rgbComponents, let theirs = other.rgbComponents else { return nil }
        switch method {
        case .ok:
            let one = Self.oklab(red: mine.red, green: mine.green, blue: mine.blue)
            let two = Self.oklab(red: theirs.red, green: theirs.green, blue: theirs.blue)
            let (lightness, greenRed, blueYellow) = (one.l - two.l, one.a - two.a, one.b - two.b)
            let squared: Double = lightness * lightness + greenRed * greenRed + blueYellow * blueYellow
            return squared.squareRoot()
        }
    }
}
