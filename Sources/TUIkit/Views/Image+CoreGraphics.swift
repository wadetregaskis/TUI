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
        /// The pixels are drawn out of the image the first time it is drawn,
        /// and drawn as any raster image is: fitted to its frame, or filling
        /// it when ``resizable(capInsets:resizingMode:)``. `scale` is accepted
        /// and changes nothing — an image here is sized by its frame, never by
        /// its pixel count — and `label` is accepted for the accessibility a
        /// terminal does not have.
        ///
        /// - Parameters:
        ///   - cgImage: The base graphical image.
        ///   - scale: The scale factor the image was made for.
        ///   - orientation: The orientation of the image. Up by default.
        ///   - label: The label associated with the image.
        public init(_ cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up, label: Text) {
            self.init(drawingOutOf: cgImage, orientation: orientation)
        }

        /// Creates an unlabeled, decorative image based on a Core Graphics
        /// image instance — mirrors SwiftUI's
        /// `init(decorative:scale:orientation:)`.
        ///
        /// - Parameters:
        ///   - cgImage: The base graphical image.
        ///   - scale: The scale factor the image was made for. Accepted; see
        ///     ``init(_:scale:orientation:label:)``.
        ///   - orientation: The orientation of the image. Up by default.
        public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Orientation = .up) {
            self.init(drawingOutOf: cgImage, orientation: orientation)
        }

        /// Creates a SwiftUI image from an AppKit image instance — mirrors
        /// SwiftUI's `init(nsImage:)`.
        ///
        /// The image is drawn out once, the first time it is drawn: an
        /// `NSImage` drawn into after that is not drawn again.
        ///
        /// - Parameter nsImage: The AppKit image to wrap.
        public init(nsImage: NSImage) {
            self.init(.url("tuikit-nsimage:\(Self.address(of: nsImage))"))
            self.decoded = _DecodedImage(owner: nsImage) {
                var rect = CGRect(origin: .zero, size: nsImage.size)
                guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                    return RGBAImage(width: 0, height: 0, pixels: [])
                }
                return Self.pixels(of: cgImage)
            }
        }

        private init(drawingOutOf cgImage: CGImage, orientation: Orientation) {
            self.init(.url("tuikit-cgimage:\(Self.address(of: cgImage))/\(orientation.rawValue)"))
            self.decoded = _DecodedImage(owner: cgImage) { Self.pixels(of: cgImage).oriented(orientation) }
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
