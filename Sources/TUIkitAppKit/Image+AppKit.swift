//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+AppKit.swift
//
//  SwiftUI's images made from pixels the app already has — a `CGImage` or an
//  `NSImage`. Here, in `TUIkitAppKit`, rather than in `TUIkit`: see
//  `Exports.swift` in this module for why.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(AppKit)
    import AppKit
    import TUIkitFoundation

    extension Image {
        /// Creates a labeled image based on a Core Graphics image instance —
        /// mirrors SwiftUI's `init(_:scale:orientation:label:)`.
        ///
        /// Its natural size is its pixels over `scale`, in points, as SwiftUI's
        /// is: a 200 × 100-pixel image made at scale 2 is 100 × 50 points, so
        /// in a 7 × 14-point cell 14 × 4 cells (see the `Image` type's
        /// *Sizing*). Made resizable, or where the terminal's cell size in
        /// points is not known, it is drawn as any raster image is — filling
        /// or fitted to its frame — and the scale does not enter into it.
        /// `label` is accepted for the accessibility a terminal does not have.
        ///
        /// > Important: **The image is named by its object's address, and its
        /// > pixels are drawn out of it once.** The first time it is drawn, its
        /// > pixels are read and kept, under a name made from the `CGImage`'s
        /// > address (with the orientation and scale), and every later frame
        /// > draws what was read. A `CGImage` is immutable, so for one this is
        /// > only a statement of the mechanism; but a new `CGImage` that happens
        /// > to reuse a freed one's address is a new name only because the view
        /// > holds the image it drew for as long as it draws it. Comparing the
        /// > pixels instead would mean hashing them on every frame. See
        /// > `Documentation/SwiftUI-compatibility.md` (decisions B43).
        ///
        /// - Parameters:
        ///   - cgImage: The base graphical image.
        ///   - scale: The scale factor the image was made for: pixels per point.
        ///   - orientation: The orientation of the image. Up by default.
        ///   - label: The label associated with the image.
        public init(_ cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up, label: Text) {
            self.init(drawingOutOf: cgImage, scale: Double(scale), orientation: orientation)
        }

        /// Creates an unlabeled, decorative image based on a Core Graphics
        /// image instance — mirrors SwiftUI's
        /// `init(decorative:scale:orientation:)`.
        ///
        /// Sized and drawn as `init(_:scale:orientation:label:)` is — its
        /// pixels over `scale` are its natural size, and its pixels are drawn
        /// out of it once, named by its address.
        ///
        /// - Parameters:
        ///   - cgImage: The base graphical image.
        ///   - scale: The scale factor the image was made for: pixels per point.
        ///   - orientation: The orientation of the image. Up by default.
        public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up) {
            self.init(drawingOutOf: cgImage, scale: Double(scale), orientation: orientation)
        }

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
        /// > picture's size. See `Documentation/SwiftUI-compatibility.md`
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

        /// The scale is in the name as well as in the pixels' sizing, so an
        /// image shown at another scale is another image to a memo that
        /// compares images — their sizes differ.
        private init(drawingOutOf cgImage: CGImage, scale: Double, orientation: Orientation) {
            let scale = _DecodedImage.sanitized(scale)
            let name = "tuikit-cgimage:\(Self.address(of: cgImage))/\(orientation.rawValue)"
            let decoded = _DecodedImage(owner: cgImage, pointSizing: .scale(scale)) {
                Self.pixels(of: cgImage).oriented(orientation)
            }
            self.init(.url(scale == 1 ? name : "\(name)@\(scale)x"), decoded: decoded)
        }

        /// The address that names an image the app handed over — unique for as
        /// long as the image lives, which `_DecodedImage.owner` sees to.
        private static func address(of object: AnyObject) -> String {
            String(UInt(bitPattern: ObjectIdentifier(object).hashValue), radix: 16)
        }

        /// `cgImage`'s pixels, or none if it cannot be drawn out.
        private static func pixels(of cgImage: CGImage) -> RGBAImage {
            (try? PlatformImageLoader().decode(cgImage, maxPixelCount: nil))
                ?? RGBAImage(width: 0, height: 0, pixels: [])
        }
    }
#endif
