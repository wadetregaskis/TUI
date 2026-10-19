//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FrameResize.swift
//
//  Where a rectangular frame is resized from and which way it may go:
//  SwiftUI's vocabulary for `PointerStyle.frameResize(position:directions:)`.
//  Raw values and set bits are SwiftUI's own, read off a SwiftUI build
//  (macOS 15.8), not guessed.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - FrameResizePosition

/// A place on the perimeter of a rectangular frame — an edge or a corner —
/// from which the frame is resized.
public enum FrameResizePosition: Int8, CaseIterable, Hashable, Sendable {
    /// The top edge.
    case top
    /// The leading (left) edge.
    case leading
    /// The bottom edge.
    case bottom
    /// The trailing (right) edge.
    case trailing
    /// The top-leading corner.
    case topLeading
    /// The top-trailing corner.
    case topTrailing
    /// The bottom-leading corner.
    case bottomLeading
    /// The bottom-trailing corner.
    case bottomTrailing
}

// MARK: - FrameResizeDirection

/// The direction in which a rectangular frame can be resized.
public enum FrameResizeDirection: Int8, CaseIterable, Hashable, Sendable {
    /// Inwards, to be smaller.
    case inward
    /// Outwards, to be larger.
    case outward

    /// An efficient set of frame resize directions.
    public struct Set: OptionSet, Hashable, Sendable {
        /// The raw bitmask value for this direction set.
        public let rawValue: Int8

        /// Creates a direction set from a raw bitmask value.
        ///
        /// - Parameter rawValue: The bitmask value.
        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        /// Creates a set containing the one direction given.
        ///
        /// - Parameter direction: The direction the set contains.
        public init(_ direction: FrameResizeDirection) {
            self.init(rawValue: 1 << direction.rawValue)
        }

        /// Inwards only.
        public static let inward = Self(.inward)

        /// Outwards only.
        public static let outward = Self(.outward)

        /// Inwards and outwards.
        public static let all: Self = [.inward, .outward]
    }
}
