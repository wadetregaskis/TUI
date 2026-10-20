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
        /// The colour is read once, in sRGB. A dynamic AppKit colour —
        /// `NSColor.labelColor`, say — is taken at the appearance in force when
        /// this runs, rather than following it as SwiftUI's does: a terminal's
        /// colours follow the palette instead.
        ///
        /// - Parameter nsColor: The colour to convert.
        public init(nsColor: NSColor) {
            let sRGB = nsColor.usingColorSpace(.extendedSRGB) ?? nsColor.usingColorSpace(.sRGB)
            guard let sRGB else {
                self.init(cgColor: nsColor.cgColor)
                return
            }
            self.init(
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
