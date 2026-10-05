//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+CoreGraphics.swift
//
//  SwiftUI's images made from pixels the app already has — a `CGImage` or an
//  `NSImage` — and the orientations a `CGImage` is drawn in.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitImage

#if canImport(AppKit)
    import AppKit
#endif

extension Image {
    /// The orientation of an image — mirrors SwiftUI's `Image.Orientation`.
    ///
    /// Each names how the image is turned from the orientation of its
    /// original pixel data. The raw values are SwiftUI's (measured on macOS
    /// 15).
    @frozen
    public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {
        /// The original pixel data matches the image's intended display
        /// orientation.
        case up = 0

        /// A horizontal flip of the image from the orientation of its
        /// original pixel data.
        case upMirrored = 2

        /// A 180° rotation of the image from the orientation of its original
        /// pixel data.
        case down = 6

        /// A vertical flip of the image from the orientation of its original
        /// pixel data.
        case downMirrored = 4

        /// A 90° counterclockwise rotation from the orientation of its
        /// original pixel data.
        case left = 1

        /// A 90° clockwise rotation and horizontal flip of the image from the
        /// orientation of its original pixel data.
        case leftMirrored = 3

        /// A 90° clockwise rotation of the image from the orientation of its
        /// original pixel data.
        case right = 7

        /// A 90° counterclockwise rotation and horizontal flip of the image
        /// from the orientation of its original pixel data.
        case rightMirrored = 5
    }
}

extension RGBAImage {
    /// The image turned to `orientation`, as SwiftUI draws it (measured on
    /// macOS 15 with a numbered 2 × 3 image).
    func oriented(_ orientation: Image.Orientation) -> RGBAImage {
        guard orientation != .up, width > 0, height > 0 else { return self }
        let turns: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: turns = true
        case .up, .upMirrored, .down, .downMirrored: turns = false
        }
        let columns = turns ? height : width
        let rows = turns ? width : height
        var out: [RGBA] = []
        out.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let (x, y): (Int, Int)
                switch orientation {
                case .up: (x, y) = (column, row)
                case .upMirrored: (x, y) = (width - 1 - column, row)
                case .down: (x, y) = (width - 1 - column, height - 1 - row)
                case .downMirrored: (x, y) = (column, height - 1 - row)
                case .left: (x, y) = (width - 1 - row, column)
                case .leftMirrored: (x, y) = (row, column)
                case .right: (x, y) = (row, height - 1 - column)
                case .rightMirrored: (x, y) = (width - 1 - row, height - 1 - column)
                }
                out.append(pixels[y * width + x])
            }
        }
        return RGBAImage(width: columns, height: rows, pixels: out)
    }
}

#if canImport(AppKit)
    extension Image {
        /// Creates a labeled image based on a Core Graphics image instance —
        /// mirrors SwiftUI's `init(_:scale:orientation:label:)`.
        ///
        /// Its natural size is its pixels over `scale`, in points, as SwiftUI's
        /// is: a 200 × 100-pixel image made at scale 2 is 100 × 50 points, so
        /// in a 7 × 14-point cell 14 × 4 cells (see the ``Image`` type's
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
        /// Sized and drawn as ``init(_:scale:orientation:label:)`` is — its
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
        /// is (see the ``Image`` type's *Sizing*).
        ///
        /// > Important: **An `NSImage` drawn into after it was first drawn
        /// > keeps its first pixels.** The image is named by the `NSImage`'s
        /// > address, and its pixels are drawn out of it once, the first time
        /// > it is drawn; every later frame draws what was read then. An app
        /// > that draws into an `NSImage` in place (`lockFocus`, adding a
        /// > representation) and shows it again sees the old picture, where
        /// > SwiftUI shows the new one. Make a new `NSImage` for a new picture.
        /// > Noticing an edit in place would mean hashing the pixels on every
        /// > frame, at a cost in proportion to the picture's size. See
        /// > `Documentation/SwiftUI-compatibility.md` (decisions B43).
        ///
        /// - Parameter nsImage: The AppKit image to wrap.
        public init(nsImage: NSImage) {
            self.init(.url("tuikit-nsimage:\(Self.address(of: nsImage))"))
            let size = nsImage.size
            self.decoded = _DecodedImage(
                owner: nsImage, pointSizing: .points(width: Double(size.width), height: Double(size.height))
            ) {
                var rect = CGRect(origin: .zero, size: nsImage.size)
                guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                    return RGBAImage(width: 0, height: 0, pixels: [])
                }
                return Self.pixels(of: cgImage)
            }
        }

        /// The scale is in the name as well as in the pixels' sizing, so an
        /// image shown at another scale is another image to a memo that
        /// compares images — their sizes differ.
        private init(drawingOutOf cgImage: CGImage, scale: Double, orientation: Orientation) {
            let scale = _DecodedImage.sanitized(scale)
            let name = "tuikit-cgimage:\(Self.address(of: cgImage))/\(orientation.rawValue)"
            self.init(.url(scale == 1 ? name : "\(name)@\(scale)x"))
            self.decoded = _DecodedImage(owner: cgImage, pointSizing: .scale(scale)) {
                Self.pixels(of: cgImage).oriented(orientation)
            }
        }

        /// The address that names an image the app handed over — unique for as
        /// long as the image lives, which ``_DecodedImage/owner`` sees to.
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
