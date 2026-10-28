//  🖥️ TUI — A Terminal UI framework for Swift
//  Color+ColorSpaces.swift
//
//  Created by LAYERED.work
//  License: MIT

// Color-space conversions: constructors that build an RGB ``Color`` from HSL /
// HSB / CMYK components, and the matching inverses that decompose an RGB triple
// back into each model.
//
// Terminals are an RGB (additive) medium, so every model ultimately resolves to
// `.rgb`. HSL and HSB are alternative *coordinates* on the same RGB gamut and
// round-trip exactly (modulo 8-bit rounding). CMYK is a subtractive print model
// included for parity with desktop colour pickers; the naive device conversion
// used here is fully reversible for in-gamut values but does not model ink or a
// colour profile — it is a convenience for viewing/entering values, not a
// print-accurate transform.

extension Color {

    // MARK: - HSL

    /// Creates a color from HSL values.
    ///
    /// - Parameters:
    ///   - hue: The hue component (0-360).
    ///   - saturation: The saturation component (0-100).
    ///   - lightness: The lightness component (0-100).
    /// - Returns: The corresponding RGB color.
    public static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Self {
        // Put the hue on the circle HERE, once, as `hsb` does, rather than
        // trusting the two single-shot `if`s in `hueToRGB` below. Those are
        // handed the hue a third of a turn either side, so they absorb one
        // turn of overshoot and no more: sound for 0..<360, wrong outside it.
        // `hueRotation` hands over `(hue + amount).truncatingRemainder(dividingBy: 360)`,
        // which keeps the sign, so below -240 degrees the blue argument was
        // still negative after its `+= 1`, took the first segment's ramp below
        // `luminance` and clamped: `.degrees(-300)` on rgb(255, 128, 128) drew
        // blue 1, not 128. Past 600 degrees the red argument stayed above 1
        // after its `-= 1`, and `hsl(720, 100, 50)` came out black, not red.
        //
        // An in-range hue is untouched (`truncatingRemainder` of a value
        // already in 0..<360 is exact), so no palette or picker colour moves.
        // A non-finite hue is deliberately NOT folded to 0 the way `hsb` folds
        // it: that guard is for `hsb`'s trapping `Int(...)`, which `hsl` has
        // none of. NaN stays NaN, fails every comparison in `hueToRGB` and
        // draws the grey it always drew.
        var wrappedHue = hue.truncatingRemainder(dividingBy: 360)
        if wrappedHue < 0 { wrappedHue += 360 }
        let normalizedHue = wrappedHue / 360.0
        let normalizedSaturation = saturation / 100.0
        let normalizedLightness = lightness / 100.0

        if normalizedSaturation <= 0 {
            // Achromatic (gray)
            let gray = clampedByte(normalizedLightness * 255)
            return .rgb(gray, gray, gray)
        }

        let chromaFactor =
            normalizedLightness < 0.5
            ? normalizedLightness * (1 + normalizedSaturation)
            : normalizedLightness + normalizedSaturation - normalizedLightness * normalizedSaturation
        let luminanceFactor = 2 * normalizedLightness - chromaFactor

        func hueToRGB(_ luminance: Double, _ chroma: Double, _ hueComponent: Double) -> Double {
            var adjustedHue = hueComponent
            if adjustedHue < 0 { adjustedHue += 1 }
            if adjustedHue > 1 { adjustedHue -= 1 }
            if adjustedHue < 1 / 6 { return luminance + (chroma - luminance) * 6 * adjustedHue }
            if adjustedHue < 1 / 2 { return chroma }
            if adjustedHue < 2 / 3 { return luminance + (chroma - luminance) * (2 / 3 - adjustedHue) * 6 }
            return luminance
        }

        let red = clampedByte(hueToRGB(luminanceFactor, chromaFactor, normalizedHue + 1 / 3) * 255)
        let green = clampedByte(hueToRGB(luminanceFactor, chromaFactor, normalizedHue) * 255)
        let blue = clampedByte(hueToRGB(luminanceFactor, chromaFactor, normalizedHue - 1 / 3) * 255)

        return .rgb(red, green, blue)
    }

    /// Converts RGB components to HSL (hue 0–360, saturation 0–100, lightness 0–100).
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (hue, saturation, lightness) in their standard ranges.
    public static func rgbToHSL(red: UInt8, green: UInt8, blue: UInt8) -> (hue: Double, saturation: Double, lightness: Double) {
        let normalizedRed = Double(red) / 255.0
        let normalizedGreen = Double(green) / 255.0
        let normalizedBlue = Double(blue) / 255.0

        let maxComponent = max(normalizedRed, normalizedGreen, normalizedBlue)
        let minComponent = min(normalizedRed, normalizedGreen, normalizedBlue)
        let delta = maxComponent - minComponent

        let lightness = (maxComponent + minComponent) / 2.0

        guard delta > 0 else {
            // Achromatic (gray)
            return (hue: 0, saturation: 0, lightness: lightness * 100)
        }

        let saturation: Double
        if lightness < 0.5 {
            saturation = delta / (maxComponent + minComponent)
        } else {
            saturation = delta / (2.0 - maxComponent - minComponent)
        }

        let hue = Self.hueDegrees(
            red: normalizedRed, green: normalizedGreen, blue: normalizedBlue,
            max: maxComponent, delta: delta)

        return (hue: hue, saturation: saturation * 100, lightness: lightness * 100)
    }

    /// The hue angle, in degrees, of an already-normalised RGB triple.
    ///
    /// HSL and HSB differ in what they call the third axis and how they derive
    /// saturation; they agree exactly about hue, and both carried this same
    /// ten-line switch — including the `segment < 0 ? segment + 6 : segment`
    /// wrap that keeps red's sector on the positive side of the circle.
    ///
    /// The caller has already established `delta > 0`; an achromatic colour has
    /// no hue to compute and both return 0 before reaching here.
    private static func hueDegrees(
        red: Double, green: Double, blue: Double, max maxComponent: Double, delta: Double
    ) -> Double {
        switch maxComponent {
        case red:
            let segment = (green - blue) / delta
            return 60 * (segment < 0 ? segment + 6 : segment)
        case green:
            return 60 * ((blue - red) / delta + 2)
        default:
            return 60 * ((red - green) / delta + 4)
        }
    }

    // MARK: - HSB / HSV

    /// Creates a color from HSB (a.k.a. HSV) values.
    ///
    /// HSB shares HSL's hue but differs in the second axis: HSB's *brightness*
    /// runs a fully-saturated hue (at brightness 100) to black (at 0), whereas
    /// HSL's *lightness* runs it to white at 100 and is mid-tone at 50. It is the
    /// model behind a hue/value rectangle picker.
    ///
    /// - Parameters:
    ///   - hue: The hue component (0-360).
    ///   - saturation: The saturation component (0-100).
    ///   - brightness: The brightness/value component (0-100).
    /// - Returns: The corresponding RGB color.
    public static func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double) -> Self {
        let s = saturation / 100.0
        let v = brightness / 100.0

        if s <= 0 {
            // Achromatic (gray): brightness alone sets the level.
            let gray = clampedByte(v * 255)
            return .rgb(gray, gray, gray)
        }

        // A non-finite hue would trap the `Int(...)` below — fold it to 0.
        var sector = (hue.isFinite ? hue : 0).truncatingRemainder(dividingBy: 360)
        if sector < 0 { sector += 360 }
        sector /= 60  // 0..<6

        let index = Int(sector.rounded(.down))
        let fraction = sector - Double(index)
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))

        let red: Double
        let green: Double
        let blue: Double
        switch index % 6 {
        case 0: (red, green, blue) = (v, t, p)
        case 1: (red, green, blue) = (q, v, p)
        case 2: (red, green, blue) = (p, v, t)
        case 3: (red, green, blue) = (p, q, v)
        case 4: (red, green, blue) = (t, p, v)
        default: (red, green, blue) = (v, p, q)
        }

        return .rgb(clampedByte(red * 255), clampedByte(green * 255), clampedByte(blue * 255))
    }

    /// Converts RGB components to HSB / HSV (hue 0–360, saturation 0–100,
    /// brightness 0–100).
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (hue, saturation, brightness) in their standard ranges.
    public static func rgbToHSB(red: UInt8, green: UInt8, blue: UInt8) -> (hue: Double, saturation: Double, brightness: Double) {
        let normalizedRed = Double(red) / 255.0
        let normalizedGreen = Double(green) / 255.0
        let normalizedBlue = Double(blue) / 255.0

        let maxComponent = max(normalizedRed, normalizedGreen, normalizedBlue)
        let minComponent = min(normalizedRed, normalizedGreen, normalizedBlue)
        let delta = maxComponent - minComponent

        let brightness = maxComponent
        let saturation = maxComponent <= 0 ? 0 : delta / maxComponent

        guard delta > 0 else {
            // Achromatic (gray)
            return (hue: 0, saturation: 0, brightness: brightness * 100)
        }

        let hue = Self.hueDegrees(
            red: normalizedRed, green: normalizedGreen, blue: normalizedBlue,
            max: maxComponent, delta: delta)

        return (hue: hue, saturation: saturation * 100, brightness: brightness * 100)
    }

    // MARK: - CMYK

    /// Creates a color from CMYK values via the naive device conversion.
    ///
    /// CMYK is a subtractive (print) model; this is the standard reversible
    /// device transform, not a colour-managed one — included so a picker can
    /// show and accept CMYK numbers. Round-trips exactly with ``rgbToCMYK(red:green:blue:)``
    /// for in-gamut values.
    ///
    /// - Parameters:
    ///   - cyan: The cyan component (0-100).
    ///   - magenta: The magenta component (0-100).
    ///   - yellow: The yellow component (0-100).
    ///   - black: The key/black component (0-100).
    /// - Returns: The corresponding RGB color.
    public static func cmyk(_ cyan: Double, _ magenta: Double, _ yellow: Double, _ black: Double) -> Self {
        let c = cyan / 100.0
        let m = magenta / 100.0
        let y = yellow / 100.0
        let k = black / 100.0

        let red = 255.0 * (1 - c) * (1 - k)
        let green = 255.0 * (1 - m) * (1 - k)
        let blue = 255.0 * (1 - y) * (1 - k)

        return .rgb(clampedByte(red), clampedByte(green), clampedByte(blue))
    }

    /// Converts RGB components to CMYK (each component 0–100) via the naive
    /// device conversion.
    ///
    /// - Parameters:
    ///   - red: Red component (0–255).
    ///   - green: Green component (0–255).
    ///   - blue: Blue component (0–255).
    /// - Returns: A tuple of (cyan, magenta, yellow, black) percentages.
    public static func rgbToCMYK(red: UInt8, green: UInt8, blue: UInt8) -> (cyan: Double, magenta: Double, yellow: Double, black: Double) {
        let normalizedRed = Double(red) / 255.0
        let normalizedGreen = Double(green) / 255.0
        let normalizedBlue = Double(blue) / 255.0

        let key = 1 - max(normalizedRed, normalizedGreen, normalizedBlue)
        guard key < 1 else {
            // Pure black: cyan/magenta/yellow are undefined, report all-key.
            return (cyan: 0, magenta: 0, yellow: 0, black: 100)
        }

        let cyan = (1 - normalizedRed - key) / (1 - key)
        let magenta = (1 - normalizedGreen - key) / (1 - key)
        let yellow = (1 - normalizedBlue - key) / (1 - key)

        return (cyan: cyan * 100, magenta: magenta * 100, yellow: yellow * 100, black: key * 100)
    }
}

// MARK: - Toward Grey

extension Color {
    /// The channels `red`, `green`, `blue` moved toward the grey they read as
    /// (Rec. 709 luminance, in encoded sRGB), keeping `amount` of their colour:
    /// 1 leaves them as they are, 0 is the grey, and above 1 pushes away from
    /// it. What `.saturation(_:)` and `.grayscale(_:)` do from opposite ends,
    /// what the modal veil takes out of a page, and the same per pixel for a
    /// picture's copy, so all of them agree on a colour's grey.
    package static func saturated(
        red: UInt8, green: UInt8, blue: UInt8, keeping amount: Double
    ) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let grey = 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)
        return (
            clampedByte(grey + (Double(red) - grey) * amount),
            clampedByte(grey + (Double(green) - grey) * amount),
            clampedByte(grey + (Double(blue) - grey) * amount))
    }

    /// This colour keeping `amount` of its colour (``saturated(red:green:blue:keeping:)``),
    /// or itself where it has no RGB.
    package func saturated(keeping amount: Double) -> Color {
        guard let rgb = rgbComponents else { return self }
        let moved = Self.saturated(red: rgb.red, green: rgb.green, blue: rgb.blue, keeping: amount)
        return .rgb(moved.red, moved.green, moved.blue)
    }
}

// MARK: - Colour Effects

extension Color {
    /// This colour with `amount` (−1…1 of the full range) added to each
    /// channel, as `.brightness(_:)` draws it; itself where it has no RGB.
    package func brightened(by amount: Double) -> Color {
        mappingChannels { $0 + amount * 255 }
    }

    /// This colour's channels pushed away from (above 1) or toward (below 1)
    /// the middle grey, as `.contrast(_:)` draws it; itself where it has no RGB.
    package func contrasted(by amount: Double) -> Color {
        mappingChannels { ($0 - 127.5) * amount + 127.5 }
    }

    /// This colour with its hue turned `degrees`, its saturation and lightness
    /// kept, as `.hueRotation(_:)` draws it; itself where it has no RGB.
    package func hueRotated(byDegrees degrees: Double) -> Color {
        guard let rgb = rgbComponents else { return self }
        let hsl = Self.rgbToHSL(red: rgb.red, green: rgb.green, blue: rgb.blue)
        return Self.hsl((hsl.hue + degrees).truncatingRemainder(dividingBy: 360), hsl.saturation, hsl.lightness)
    }

    /// This colour's channels inverted, as `.colorInvert()` draws it; itself
    /// where it has no RGB.
    package var inverted: Color {
        mappingChannels { 255 - $0 }
    }

    /// This colour multiplied channel by channel by `tint`, as
    /// `.colorMultiply(_:)` draws it; itself where either has no RGB.
    package func multiplied(by tint: Color) -> Color {
        guard let rgb = rgbComponents, let other = tint.rgbComponents else { return self }
        return .rgb(
            clampedByte(Double(rgb.red) * Double(other.red) / 255),
            clampedByte(Double(rgb.green) * Double(other.green) / 255),
            clampedByte(Double(rgb.blue) * Double(other.blue) / 255))
    }

    /// Each channel through `transform`, clamped back into a byte (every
    /// effect can leave the range, and a terminal has no colour outside it);
    /// itself where it has no RGB.
    private func mappingChannels(_ transform: (Double) -> Double) -> Color {
        guard let rgb = rgbComponents else { return self }
        return .rgb(
            clampedByte(transform(Double(rgb.red))),
            clampedByte(transform(Double(rgb.green))),
            clampedByte(transform(Double(rgb.blue))))
    }
}

// MARK: - Private Helpers

/// Rounds and clamps a 0–255-scaled channel value into a `UInt8`, guarding
/// against out-of-range user input (e.g. a hand-entered HSL/HSB/CMYK value) that
/// would otherwise trap the `UInt8` conversion. Rounding (not truncation) keeps
/// the RGB↔HSB and RGB↔CMYK round-trips exact.
///
/// A non-finite input (NaN or ±∞, e.g. from a degenerate conversion) is treated
/// as 0 — `UInt8(.nan)` and `UInt8(.infinity)` both trap, so they must never
/// reach the conversion.
private func clampedByte(_ value: Double) -> UInt8 {
    guard value.isFinite else { return 0 }
    return UInt8(max(0, min(255, value.rounded())))
}
