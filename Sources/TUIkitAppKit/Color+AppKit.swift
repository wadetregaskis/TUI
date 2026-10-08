//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+AppKit.swift
//
//  A colour to and from Apple's colour types: `CGColor` and `NSColor`. Here,
//  in `TUIkitAppKit`, rather than in `TUIkit`: see `Exports.swift` in this
//  module for why.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)
    import AppKit
#elseif canImport(CoreGraphics)
    import CoreGraphics
#endif

import TUIkitFoundation

#if canImport(CoreGraphics)
    extension Color.Resolved {
        /// A Core Graphics representation of the colour, in extended sRGB.
        public var cgColor: CGColor {
            CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(opacity))
        }
    }

    extension Color {
        /// Creates a colour from a Core Graphics colour, converted to sRGB.
        ///
        /// - Parameter cgColor: The colour to convert.
        public init(cgColor: CGColor) {
            let sRGB = CGColorSpace(name: CGColorSpace.extendedSRGB).flatMap {
                cgColor.converted(to: $0, intent: .defaultIntent, options: nil)
            }
            let components = (sRGB ?? cgColor).components ?? []
            let channel = { (index: Int) in Float(index < components.count ? components[index] : 0) }
            // A converted colour is red, green, blue, alpha; a grey one that
            // failed to convert is white, alpha.
            if components.count >= 4 {
                self.init(Resolved(red: channel(0), green: channel(1), blue: channel(2), opacity: channel(3)))
            } else {
                self.init(Resolved(red: channel(0), green: channel(0), blue: channel(0), opacity: channel(1)))
            }
        }
    }
#endif

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
