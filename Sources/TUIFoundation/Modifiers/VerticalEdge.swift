//  🖥️ TUI — A Terminal UI framework for Swift
//  VerticalEdge.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Vertical Edge Set

/// An edge on the vertical axis.
///
/// Used, among other things, for specifying which edges of a list row should
/// have separators. Raw values and the `Codable` encoding are SwiftUI's; see
/// `Directions.swift` for its one-axis siblings.
public enum VerticalEdge: Int8, CaseIterable, Codable, Hashable, Sendable {
    /// The top edge.
    case top

    /// The bottom edge.
    case bottom

    /// A set of vertical edges.
    public struct Set: OptionSet, Hashable, Sendable {
        /// The raw bitmask value for this edge set.
        public let rawValue: Int8

        /// Creates an edge set from a raw bitmask value.
        ///
        /// - Parameter rawValue: The bitmask value.
        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        /// Creates a set containing the one edge given — SwiftUI's
        /// `VerticalEdge.Set(_:)`, and the counterpart to ``Edge/Set/init(_:)``.
        ///
        /// - Parameter edge: The edge the set contains.
        public init(_ edge: VerticalEdge) {
            switch edge {
            case .top: self = .top
            case .bottom: self = .bottom
            }
        }

        /// The top edge only.
        public static let top = Self(rawValue: 1 << 0)

        /// The bottom edge only.
        public static let bottom = Self(rawValue: 1 << 1)

        /// All edges (top and bottom).
        public static let all: Set = [.top, .bottom]
    }
}
