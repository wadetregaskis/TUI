//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Image+Orientation.swift
//
//  The orientations an image is drawn in. The images made from a `CGImage` or
//  an `NSImage`, which take one, are in the `TUIkitAppKit` module.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitImage

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
    package func oriented(_ orientation: Image.Orientation) -> RGBAImage {
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
