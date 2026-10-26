//  🖥️ TUI — A Terminal UI framework for Swift
//  Color+Resolved.swift
//
//  SwiftUI's colour as numbers: `Color.Resolved`, the colour spaces a
//  component colour is written in, and the initialisers that take components.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

extension Color {

    /// A profile that specifies how to interpret a colour value for display.
    public enum RGBColorSpace: Hashable, Sendable {
        /// The extended red, green, blue (sRGB) colour space.
        case sRGB

        /// The extended sRGB colour space with a linear transfer function.
        case sRGBLinear

        /// The Display P3 colour space, converted to sRGB as it is read.
        case displayP3
    }

    /// A concrete colour value: red, green, blue and opacity, stored in linear
    /// sRGB with extended range, as SwiftUI stores it.
    ///
    /// A ``Color`` made from one keeps 8 bits per channel, gamma-encoded and
    /// clamped to `0...1`, which is all a terminal can show. So a component
    /// outside that range survives in a `Resolved` and not in a `Color` made
    /// from it.
    public struct Resolved: Hashable, Sendable {
        /// The amount of red, in linear sRGB.
        public var linearRed: Float

        /// The amount of green, in linear sRGB.
        public var linearGreen: Float

        /// The amount of blue, in linear sRGB.
        public var linearBlue: Float

        /// The degree of opacity, from `0` (transparent) to `1` (opaque).
        public var opacity: Float

        /// Creates a resolved colour from red, green, and blue components in
        /// `colorSpace`, and an opacity.
        public init(colorSpace: RGBColorSpace = .sRGB, red: Float, green: Float, blue: Float, opacity: Float = 1) {
            switch colorSpace {
            case .sRGBLinear:
                (linearRed, linearGreen, linearBlue) = (red, green, blue)
            case .sRGB:
                (linearRed, linearGreen, linearBlue) = (Self.linear(red), Self.linear(green), Self.linear(blue))
            case .displayP3:
                // P3 shares sRGB's transfer curve; its primaries go to sRGB's
                // through a linear matrix, and what falls outside sRGB's gamut
                // stays as extended-range components. The matrix is SwiftUI's,
                // measured: the standard one rounded to four places.
                let (r, g, b) = (Self.linear(red), Self.linear(green), Self.linear(blue))
                linearRed = 1.2249 * r - 0.2247 * g
                linearGreen = -0.042 * r + 1.0419 * g
                linearBlue = -0.0197 * r - 0.0786 * g + 1.0979 * b
            }
            self.opacity = opacity
        }

        /// The amount of red in the colour in the sRGB colour space.
        public var red: Float {
            get { Self.encoded(linearRed) }
            set { linearRed = Self.linear(newValue) }
        }

        /// The amount of green in the colour in the sRGB colour space.
        public var green: Float {
            get { Self.encoded(linearGreen) }
            set { linearGreen = Self.linear(newValue) }
        }

        /// The amount of blue in the colour in the sRGB colour space.
        public var blue: Float {
            get { Self.encoded(linearBlue) }
            set { linearBlue = Self.linear(newValue) }
        }

        /// sRGB's transfer curve decoded, mirrored through zero for the
        /// extended range — the convention SwiftUI's extended sRGB uses.
        ///
        /// Worked in `Double`, as SwiftUI's evidently is: in `Float`, `1`
        /// comes back as `0.99999994`, and SwiftUI's comes back as `1`.
        static func linear(_ value: Float) -> Float {
            let magnitude = Double(abs(value))
            let decoded = magnitude <= 0.040_45 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
            return Float(value < 0 ? -decoded : decoded)
        }

        /// The inverse of ``linear(_:)``.
        static func encoded(_ value: Float) -> Float {
            let magnitude = Double(abs(value))
            let encoded = magnitude <= 0.003_130_8 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
            return Float(value < 0 ? -encoded : encoded)
        }

        /// One gamma-encoded component as the byte a ``Color`` stores.
        static func byte(_ component: Float) -> UInt8 {
            guard component.isFinite else { return 0 }
            return UInt8((min(1, max(0, component)) * 255).rounded())
        }
    }

    /// Creates a constant colour with the values of a resolved colour.
    ///
    /// The components are stored as 8-bit sRGB, clamped to `0...1`.
    public init(_ resolved: Resolved) {
        let opaque = Self.rgb(Resolved.byte(resolved.red), Resolved.byte(resolved.green), Resolved.byte(resolved.blue))
        self = opaque.opacity(Double(resolved.opacity))
    }

    /// Creates a constant colour from red, green, and blue component values.
    ///
    /// Components outside `0...1` are clamped: a terminal shows 8-bit sRGB, so
    /// SwiftUI's extended range has nowhere to go. A Display P3 colour is
    /// converted to sRGB first.
    ///
    /// - Parameters:
    ///   - colorSpace: How to interpret the components. The default is
    ///     ``RGBColorSpace/sRGB``.
    ///   - red: The amount of red in the colour.
    ///   - green: The amount of green in the colour.
    ///   - blue: The amount of blue in the colour.
    ///   - opacity: The degree of opacity, from `0` to `1`. The default is `1`.
    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.init(
            Resolved(
                colorSpace: colorSpace, red: Float(red), green: Float(green), blue: Float(blue),
                opacity: Float(opacity)))
    }

    /// Creates a constant greyscale colour.
    ///
    /// - Parameters:
    ///   - colorSpace: How to interpret `white`. The default is
    ///     ``RGBColorSpace/sRGB``.
    ///   - white: How white the colour is, from `0` (black) to `1` (white).
    ///   - opacity: The degree of opacity, from `0` to `1`. The default is `1`.
    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
    }

    /// Creates a constant colour from hue, saturation, and brightness values.
    ///
    /// - Parameters:
    ///   - hue: A value from `0` to `1` that maps to an angle from 0° to 360°
    ///     on the colour wheel.
    ///   - saturation: From `0` (grey) to `1` (the hue at full strength).
    ///   - brightness: From `0` (black) to `1`.
    ///   - opacity: The degree of opacity, from `0` to `1`. The default is `1`.
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        self = Self.hsb(hue * 360, saturation * 100, brightness * 100).opacity(opacity)
    }
}

// MARK: - Text and storage

extension Color.Resolved: CustomStringConvertible {
    /// `#RRGGBBAA`, in gamma-encoded sRGB — SwiftUI's spelling, measured,
    /// down to its quirks: a component is scaled, offset by a half and
    /// truncated toward zero, and one out of range wraps to a 32-bit
    /// two's-complement value.
    public var description: String {
        "#" + [red, green, blue, opacity].map(Self.hex).joined()
    }

    private static func hex(_ component: Float) -> String {
        let scaled = component.isFinite ? Int64((Double(component) * 255 + 0.5).rounded(.towardZero)) : 0
        let digits = String(UInt32(truncatingIfNeeded: scaled), radix: 16, uppercase: true)
        return digits.count < 2 ? "0" + digits : digits
    }
}

/// Encoded as SwiftUI encodes it: `[red, green, blue, opacity]`, gamma-encoded
/// sRGB (measured).
extension Color.Resolved: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let red = try container.decode(Float.self)
        let green = try container.decode(Float.self)
        let blue = try container.decode(Float.self)
        let opacity = try container.decode(Float.self)
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(red)
        try container.encode(green)
        try container.encode(blue)
        try container.encode(opacity)
    }
}

extension Color: CustomStringConvertible {
    /// A constant colour as `#RRGGBBAA`, as SwiftUI spells one; a palette role,
    /// a terminal slot or the terminal's default by name.
    public var description: String {
        let name: String
        switch value {
        case .rgb(let red, let green, let blue):
            return Self.Resolved(red: Float(red) / 255, green: Float(green) / 255, blue: Float(blue) / 255,
                opacity: Float(alpha) / 255).description
        case .semantic(let token): name = token.rawValue
        // As SwiftUI describes its named colours: `red`, not the value.
        case .system(let named): name = "\(named)"
        // Both values, as a light-and-dark colour has no name to give: SwiftUI's
        // `NamedColor(name:bundle:)` names the colour set, which is not kept.
        case .lightDark(let index):
            name = "\(index.color(in: .light).opaqueSpelling) light, \(index.color(in: .dark).opaqueSpelling) dark"
        case .ansi(let slot): name = "ansi(\(slot))"
        case .palette256(let index): name = "palette256(\(index))"
        case .terminalDefault: name = "default"
        case .terminalForeground: name = "terminalForeground"
        case .terminalBackground: name = "terminalBackground"
        }
        return isOpaque ? name : "\(name) at \(alpha)/255"
    }
}
