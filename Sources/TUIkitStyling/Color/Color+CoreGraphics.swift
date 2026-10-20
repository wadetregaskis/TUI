//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Color+CoreGraphics.swift
//
//  A colour to and from Core Graphics' `CGColor`, where Core Graphics exists.
//  In TUIkit itself (decisions B-D3M-4): Core Graphics does not bring in
//  SwiftUICore, as AppKit does, so these need no other import. The AppKit
//  bridges, `Color(nsColor:)` and `NSColor(_:)`, stay in TUIkitAppKit.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
    import CoreGraphics

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
