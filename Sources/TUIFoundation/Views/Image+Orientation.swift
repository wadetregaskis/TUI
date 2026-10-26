//  🖥️ TUI — A Terminal UI framework for Swift
//  Image+Orientation.swift
//
//  The orientations an image is drawn in. The images made from a `CGImage` or
//  an `NSImage`, which take one, are in the `TUIAppKit` module.
//
//  Created by Wade Tregaskis
//  License: MIT

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
