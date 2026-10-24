//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+AppKit.swift
//
//  A colour to and from AppKit's `NSColor`. Here, in `TUIkitAppKit`, rather than
//  in `TUIkit`: see `Exports.swift` in this module for why. The `CGColor`
//  bridges are TUIkit's own (`Color+CoreGraphics.swift`, TUIkitStyling).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)
    import AppKit
#endif

import TUIkitFoundation

#if canImport(AppKit)
    extension Color {
        /// Creates a colour from an AppKit colour.
        ///
        /// The colour is read in sRGB. A dynamic AppKit colour — a catalogue's
        /// `NSColor(named:)`, `NSColor.systemTeal`, `NSColor(name:dynamicProvider:)`
        /// — is read under the light (aqua) and the dark (darkAqua) appearance,
        /// and the one drawn is the one for the colour scheme where the colour is
        /// drawn (the palette's, or a `.colorScheme` pin's), as SwiftUI's
        /// `Color(nsColor:)` follows the environment. Measured in a view body, it
        /// reads its light value.
        ///
        /// A dynamic colour whose two values differ in opacity, or one that is
        /// not a plain colour in sRGB (a pattern), is taken at the appearance in
        /// force when this runs instead: a `Color` keeps one opacity. So is every
        /// dynamic colour once a process has made 65,536 different pairs. See
        /// decisions B-D6M-4.
        ///
        /// - Parameter nsColor: The colour to convert.
        public init(nsColor: NSColor) {
            let light = Self.reading(nsColor, under: .aqua)
            let dark = Self.reading(nsColor, under: .darkAqua)
            if let light, let dark, let drawn = Self.lightDark(light: light, dark: dark) {
                self = drawn
            } else {
                self = Self.reading(nsColor)
            }
        }

        /// `nsColor` read in sRGB under the appearance `name`, or `nil` where
        /// AppKit has no such appearance.
        private static func reading(_ nsColor: NSColor, under name: NSAppearance.Name) -> Color? {
            guard let appearance = NSAppearance(named: name) else { return nil }
            var color: Color?
            appearance.performAsCurrentDrawingAppearance { color = reading(nsColor) }
            return color
        }

        /// `nsColor` read in sRGB under the appearance in force.
        private static func reading(_ nsColor: NSColor) -> Color {
            let sRGB = nsColor.usingColorSpace(.extendedSRGB) ?? nsColor.usingColorSpace(.sRGB)
            guard let sRGB else { return Color(cgColor: nsColor.cgColor) }
            return Color(
                Resolved(
                    red: Float(sRGB.redComponent), green: Float(sRGB.greenComponent), blue: Float(sRGB.blueComponent),
                    opacity: Float(sRGB.alphaComponent)))
        }
    }

    extension NSColor {
        /// Creates an AppKit colour from a colour.
        ///
        /// A palette role is resolved against the default palette, since there
        /// is no environment to ask; resolve the colour with
        /// `Color.resolve(in:)` first to use another.
        ///
        /// - Parameter color: The colour to convert.
        public convenience init(_ color: Color) {
            let resolved = color.resolve(in: EnvironmentValues())
            self.init(
                srgbRed: CGFloat(resolved.red), green: CGFloat(resolved.green), blue: CGFloat(resolved.blue),
                alpha: CGFloat(resolved.opacity))
        }
    }
#endif
