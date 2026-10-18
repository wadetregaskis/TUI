//  🖥️ TUIkit — Terminal UI Kit for Swift
//  EdgeCorner.swift
//
//  The corners of a rectangle, sets of them, and how one is rounded.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

extension Edge {
    /// A corner of a rectangle — mirrors SwiftUI's `Edge.Corner` (macOS 26).
    public enum Corner: Int8, Hashable, CaseIterable, Sendable {
        /// The top-leading corner.
        case topLeading
        /// The top-trailing corner.
        case topTrailing
        /// The bottom-leading corner.
        case bottomLeading
        /// The bottom-trailing corner.
        case bottomTrailing
    }
}

extension Edge.Corner {
    /// An efficient set of corners.
    public struct Set: OptionSet, Hashable, Sendable {
        /// The element of the set: a set, as with any option set.
        public typealias Element = Self

        /// The set's bits, a corner each.
        public let rawValue: Int8

        /// A set from its bits.
        ///
        /// - Parameter rawValue: The bits.
        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        /// The set of one corner.
        ///
        /// - Parameter corner: The corner.
        public init(_ corner: Edge.Corner) {
            self.init(rawValue: 1 << corner.rawValue)
        }

        /// No corner.
        public static let none = Self([])
        /// The top-leading corner.
        public static let topLeading = Self(.topLeading)
        /// The top-trailing corner.
        public static let topTrailing = Self(.topTrailing)
        /// The bottom-leading corner.
        public static let bottomLeading = Self(.bottomLeading)
        /// The bottom-trailing corner.
        public static let bottomTrailing = Self(.bottomTrailing)
        /// Every corner.
        public static let all: Self = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        /// The two leading corners.
        public static let leading: Self = [.topLeading, .bottomLeading]
        /// The two trailing corners.
        public static let trailing: Self = [.topTrailing, .bottomTrailing]
        /// The two bottom corners.
        public static let bottom: Self = [.bottomLeading, .bottomTrailing]
        /// The two top corners.
        public static let top: Self = [.topLeading, .topTrailing]

        /// Whether the set holds `corner`.
        ///
        /// - Parameter corner: The corner.
        /// - Returns: Whether it is in the set.
        public func contains(_ corner: Edge.Corner) -> Bool {
            contains(Self(corner))
        }
    }
}

extension Edge.Corner: CustomDebugStringConvertible {
    /// The corner's name.
    public var debugDescription: String {
        switch self {
        case .topLeading: "topLeading"
        case .topTrailing: "topTrailing"
        case .bottomLeading: "bottomLeading"
        case .bottomTrailing: "bottomTrailing"
        }
    }
}

extension Edge.Corner.Set: CustomDebugStringConvertible {
    /// The corners in the set, by name.
    public var debugDescription: String {
        "[" + Edge.Corner.allCases.filter { contains($0) }.map(\.debugDescription).joined(separator: ", ") + "]"
    }
}

// MARK: - How a corner is rounded

extension Edge.Corner {
    /// How a corner is rounded — mirrors SwiftUI's `Edge.Corner.Style`
    /// (macOS 26): a fixed radius, or concentric with the corner of the
    /// container it is in, at least some minimum.
    ///
    /// A number is a fixed radius: `RoundedRectangularShapeCorners(all: 2)`.
    /// Radii are in a shape's unit, columns (``Shape/path(in:)``).
    public struct Style: Hashable, Sendable {
        /// The fixed radius, or for a concentric corner its minimum.
        let radius: CGFloat
        /// Whether the corner follows its container's.
        let isConcentric: Bool

        /// A corner of `radius`.
        ///
        /// - Parameter radius: The radius, in columns.
        /// - Returns: The style.
        public static func fixed(_ radius: CGFloat) -> Self {
            Self(radius: radius, isConcentric: false)
        }

        /// A corner concentric with its container's: the container's radius
        /// less how far inside the container the shape lies.
        public static var concentric: Self { Self(radius: 0, isConcentric: true) }

        /// A corner concentric with its container's, but no smaller than
        /// `minimum`'s radius.
        ///
        /// - Parameter minimum: The smallest the corner may be — a fixed radius;
        ///   a concentric minimum means none.
        /// - Returns: The style.
        public static func concentric(minimum: Self? = nil) -> Self {
            Self(radius: minimum.map { $0.isConcentric ? 0 : $0.radius } ?? 0, isConcentric: true)
        }

        /// The radius this corner draws at, where its container's corner — if
        /// it has one — is `container` and it lies `inset` inside it.
        func radius(container: CGFloat?, inset: CGFloat) -> CGFloat {
            guard isConcentric else { return max(0, radius) }
            return max(radius, (container ?? 0) - inset, 0)
        }
    }
}

extension Edge.Corner.Style: ExpressibleByFloatLiteral {
    /// A fixed radius written as a decimal.
    public typealias FloatLiteralType = Float

    /// A fixed radius written as a decimal.
    ///
    /// - Parameter value: The radius.
    public init(floatLiteral value: Float) {
        self = .fixed(CGFloat(value))
    }
}

extension Edge.Corner.Style: ExpressibleByIntegerLiteral {
    /// A fixed radius written as a whole number.
    public typealias IntegerLiteralType = Int

    /// A fixed radius written as a whole number.
    ///
    /// - Parameter value: The radius.
    public init(integerLiteral value: Int) {
        self = .fixed(CGFloat(value))
    }
}

extension Edge.Corner.Style: Animatable {
    /// A corner style's animatable data: its radius — the fixed one, or a
    /// concentric corner's minimum.
    public struct AnimatableData: VectorArithmetic, Sendable {
        var radius: CGFloat

        /// No radius.
        public static var zero: Self { Self(radius: 0) }

        /// The sum of two radii.
        public static func + (lhs: Self, rhs: Self) -> Self { Self(radius: lhs.radius + rhs.radius) }

        /// The difference of two radii.
        public static func - (lhs: Self, rhs: Self) -> Self { Self(radius: lhs.radius - rhs.radius) }

        /// The radius scaled by `rhs`.
        public mutating func scale(by rhs: Double) { radius *= CGFloat(rhs) }

        /// The radius squared.
        public var magnitudeSquared: Double { Double(radius * radius) }
    }

    /// The radius, animated; whether the corner is concentric does not.
    public var animatableData: AnimatableData {
        get { AnimatableData(radius: radius) }
        set { self = Self(radius: newValue.radius, isConcentric: isConcentric) }
    }
}

extension RectangleCornerRadii {
    /// The radius of `corner`.
    ///
    /// - Parameter corner: The corner.
    public subscript(corner: Edge.Corner) -> CGFloat {
        switch corner {
        case .topLeading: topLeading
        case .topTrailing: topTrailing
        case .bottomLeading: bottomLeading
        case .bottomTrailing: bottomTrailing
        }
    }
}
