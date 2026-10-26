//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+AppKit.swift
//
//  SwiftUI's image made from an `NSImage` the app already has. Here, in
//  `TUIAppKit`, rather than in `TUI`: see `Exports.swift` in this module
//  for why. The `CGImage` ones are TUI's own (`Image+CoreGraphics.swift`,
//  TUIBitmaps).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)
    import AppKit
    import TUIBitmaps
    import TUIFoundation

    extension Image {
        /// Creates a SwiftUI image from an AppKit image instance — mirrors
        /// SwiftUI's `init(nsImage:)`.
        ///
        /// Its natural size is the `NSImage`'s `size`, in points, as SwiftUI's
        /// is (see the `Image` type's *Sizing*). The size is read when the
        /// `Image` is made, and is part of its name, so an `NSImage` given a
        /// new `size` and shown again is a new image: drawn out afresh, at
        /// its new size, and unequal to the old one for a memo that compares
        /// them.
        ///
        /// > Important: **An `NSImage` drawn into after it was first drawn
        /// > keeps its first pixels.** The image is named by the `NSImage`'s
        /// > address and size, and its pixels are drawn out of it once, the
        /// > first time it is drawn; every later frame draws what was read
        /// > then. An app that draws into an `NSImage` in place (`lockFocus`,
        /// > adding a representation) and shows it again at the same size sees
        /// > the old picture, where SwiftUI shows the new one. Make a new
        /// > `NSImage` for a new picture. Noticing an edit in place would mean
        /// > hashing the pixels on every frame, at a cost in proportion to the
        /// > picture's size. See `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`
        /// > (decisions B43).
        ///
        /// - Parameter nsImage: The AppKit image to wrap.
        public init(nsImage: NSImage) {
            let size = nsImage.size
            let decoded = _DecodedImage(
                owner: nsImage, pointSizing: .points(width: Double(size.width), height: Double(size.height))
            ) {
                var rect = CGRect(origin: .zero, size: size)  // the size named, not a later one
                guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                    return RGBAImage(width: 0, height: 0, pixels: [])
                }
                return Self.pixels(of: cgImage)
            }
            self.init(
                .url("tuikit-nsimage:\(Self.address(of: nsImage))/\(Double(size.width))x\(Double(size.height))"),
                decoded: decoded)
        }
    }
#endif
