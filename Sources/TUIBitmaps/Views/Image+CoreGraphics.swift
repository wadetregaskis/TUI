//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+CoreGraphics.swift
//
//  SwiftUI's images made from a `CGImage` the app already has, where Core
//  Graphics exists. In TUI itself (decisions B-D3M-4): Core Graphics does
//  not bring in SwiftUICore, as AppKit does, so these need no other import.
//  `Image(nsImage:)` stays in TUIAppKit, and draws through the helpers here.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
    import CoreGraphics
    import TUIFoundation
    import TUIImage

    @MainActor extension Image {
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
        /// > `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (decisions B43).
        ///
        /// - Parameters:
        ///   - cgImage: The base graphical image.
        ///   - scale: The scale factor the image was made for: pixels per point.
        ///   - orientation: The orientation of the image. Up by default.
        ///   - label: The label associated with the image.
        nonisolated public init(_ cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up, label: Text) {
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
        nonisolated public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up) {
            self.init(drawingOutOf: cgImage, scale: Double(scale), orientation: orientation)
        }

        /// The scale is in the name as well as in the pixels' sizing, so an
        /// image shown at another scale is another image to a memo that
        /// compares images — their sizes differ.
        nonisolated package init(drawingOutOf cgImage: CGImage, scale: Double, orientation: Orientation) {
            let scale = _DecodedImage.sanitized(scale)
            let name = "tuikit-cgimage:\(Self.address(of: cgImage))/\(orientation.rawValue)"
            let decoded = _DecodedImage(owner: cgImage, pointSizing: .scale(scale)) {
                Self.pixels(of: cgImage).oriented(orientation)
            }
            self.init(.url(scale == 1 ? name : "\(name)@\(scale)x"), decoded: decoded)
        }

        /// The address that names an image the app handed over — unique for as
        /// long as the image lives, which `_DecodedImage.owner` sees to.
        nonisolated package static func address(of object: AnyObject) -> String {
            String(UInt(bitPattern: ObjectIdentifier(object).hashValue), radix: 16)
        }

        /// `cgImage`'s pixels, or none if it cannot be drawn out.
        nonisolated package static func pixels(of cgImage: CGImage) -> RGBAImage {
            (try? PlatformImageLoader().decode(cgImage, maxPixelCount: nil))
                ?? RGBAImage(width: 0, height: 0, pixels: [])
        }
    }
#endif
