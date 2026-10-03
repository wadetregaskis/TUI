//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Directions.swift
//
//  The one-axis edges and directions SwiftUI names as types of their own, for
//  APIs that only ever mean one axis: a swipe comes from a horizontal edge, a
//  scroll heads up or down. Each mirrors ``Edge``: the enum is a single value,
//  and its nested `Set` is an option set of them. Raw values, set bits and the
//  `Codable` encoding (the raw value) are SwiftUI's own, read off a SwiftUI
//  build rather than guessed, so a value persisted by one framework reads back
//  in the other.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - HorizontalEdge

/// An edge on the horizontal axis.
///
/// The leading edge is the left one: TUIkit lays out left to right.
public enum HorizontalEdge: Int8, CaseIterable, Codable, Hashable, Sendable {
    /// The leading (left) edge.
    case leading

    /// The trailing (right) edge.
    case trailing

    /// An efficient set of horizontal edges.
    public struct Set: OptionSet, Hashable, Sendable {
        /// The raw bitmask value for this edge set.
        public let rawValue: Int8

        /// Creates an edge set from a raw bitmask value.
        ///
        /// - Parameter rawValue: The bitmask value.
        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        /// Creates a set containing the one edge given.
        ///
        /// - Parameter edge: The edge the set contains.
        public init(_ edge: HorizontalEdge) {
            self.init(rawValue: 1 << edge.rawValue)
        }

        /// The leading edge only.
        public static let leading = Self(.leading)

        /// The trailing edge only.
        public static let trailing = Self(.trailing)

        /// Both horizontal edges.
        public static let all: Self = [.leading, .trailing]
    }
}

// MARK: - HorizontalDirection

/// A direction on the horizontal axis.
///
/// Leading is towards the left: TUIkit lays out left to right.
public enum HorizontalDirection: Int8, CaseIterable, Codable, Hashable, Sendable {
    /// Towards the leading (left) edge.
    case leading

    /// Towards the trailing (right) edge.
    case trailing

    /// An efficient set of horizontal directions.
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
        public init(_ direction: HorizontalDirection) {
            self.init(rawValue: 1 << direction.rawValue)
        }

        /// The leading direction only.
        public static let leading = Self(.leading)

        /// The trailing direction only.
        public static let trailing = Self(.trailing)

        /// Both horizontal directions.
        public static let all: Self = [.leading, .trailing]
    }
}

// MARK: - VerticalDirection

/// A direction on the vertical axis.
public enum VerticalDirection: Int8, CaseIterable, Codable, Hashable, Sendable {
    /// Upwards, towards the top edge.
    case up

    /// Downwards, towards the bottom edge.
    case down

    /// An efficient set of vertical directions.
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
        public init(_ direction: VerticalDirection) {
            self.init(rawValue: 1 << direction.rawValue)
        }

        /// The upward direction only.
        public static let up = Self(.up)

        /// The downward direction only.
        public static let down = Self(.down)

        /// Both vertical directions.
        public static let all: Self = [.up, .down]
    }
}
