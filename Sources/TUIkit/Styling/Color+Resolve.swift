//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+Resolve.swift
//
//  A colour resolved against an environment to numbers, and the resolved
//  value as a style and an animatable — the half of `Color.Resolved` that
//  needs the environment and the animation types.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitStyling

#if canImport(AppKit)
    import AppKit
#elseif canImport(CoreGraphics)
    import CoreGraphics
#endif

extension Color {
    /// Evaluates this colour within the given environment: its palette role, or
    /// the colour the terminal reported for a slot, as numbers.
    ///
    /// A terminal slot the terminal has not reported reads as xterm's value for
    /// it. The terminal's default ink and page are not known until reported;
    /// meanwhile they read as white and black on a dark scheme, black and white
    /// on a light one.
    ///
    /// - Parameter environment: The environment to resolve in.
    /// - Returns: The colour's components.
    public func resolve(in environment: EnvironmentValues) -> Resolved {
        let resolved = resolve(with: environment.palette)
        let opacity = Float(resolved.alpha) / 255
        if let (red, green, blue) = resolved.estimatedRGB {
            return Resolved(red: Float(red) / 255, green: Float(green) / 255, blue: Float(blue) / 255, opacity: opacity)
        }
        let isPage = resolved.value == .terminalBackground
        let light: Float = (environment.colorScheme == .dark) == isPage ? 0 : 1
        return Resolved(red: light, green: light, blue: light, opacity: opacity)
    }
}

extension Color.Resolved: ShapeStyle {
    public typealias Resolved = Never

    public func paint(in environment: EnvironmentValues) -> Paint {
        .color(Color(self))
    }
}

extension Color.Resolved: Animatable {
    /// The linear components and the opacity. SwiftUI animates a resolved
    /// colour in a space of its own that it does not document; linear light is
    /// what this one interpolates in.
    public typealias AnimatableData = AnimatablePair<Float, AnimatablePair<Float, AnimatablePair<Float, Float>>>

    public var animatableData: AnimatableData {
        get { AnimatablePair(linearRed, AnimatablePair(linearGreen, AnimatablePair(linearBlue, opacity))) }
        set {
            linearRed = newValue.first
            linearGreen = newValue.second.first
            linearBlue = newValue.second.second.first
            opacity = newValue.second.second.second
        }
    }
}

// MARK: - Apple's colour types

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
        /// ``Color/resolve(in:)`` first to use another.
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
