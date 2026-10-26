//  🖥️ TUI — A Terminal UI framework for Swift
//  RoundedRectangularShape.swift
//
//  The shapes whose outline is a rectangle with four rounded corners, and the
//  corners they say they have.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - The corners

/// The corners of a rounded rectangular shape — mirrors SwiftUI's
/// `RoundedRectangularShapeCorners` (macOS 26).
public struct RoundedRectangularShapeCorners: Sendable, Hashable {
    /// The top-leading corner.
    public var topLeading: Edge.Corner.Style
    /// The bottom-leading corner.
    public var bottomLeading: Edge.Corner.Style
    /// The top-trailing corner.
    public var topTrailing: Edge.Corner.Style
    /// The bottom-trailing corner.
    public var bottomTrailing: Edge.Corner.Style

    /// Corners styled one by one; a corner not given is square.
    ///
    /// - Parameters:
    ///   - topLeading: The top-leading corner.
    ///   - topTrailing: The top-trailing corner.
    ///   - bottomLeading: The bottom-leading corner.
    ///   - bottomTrailing: The bottom-trailing corner.
    public init(
        topLeading: Edge.Corner.Style = 0, topTrailing: Edge.Corner.Style = 0, bottomLeading: Edge.Corner.Style = 0,
        bottomTrailing: Edge.Corner.Style = 0
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    /// Every corner styled alike.
    ///
    /// - Parameter all: The style of each corner.
    public init(all: Edge.Corner.Style) {
        self.init(topLeading: all, topTrailing: all, bottomLeading: all, bottomTrailing: all)
    }

    /// Every corner of `radius`.
    ///
    /// - Parameter radius: The radius, in columns.
    /// - Returns: The corners.
    public static func fixed(_ radius: CGFloat) -> Self {
        Self(all: .fixed(radius))
    }

    /// Every corner concentric with its container's.
    public static var concentric: Self { Self(all: .concentric) }

    /// Every corner concentric with its container's, no smaller than
    /// `minimum`.
    ///
    /// - Parameter minimum: The smallest a corner may be.
    /// - Returns: The corners.
    public static func concentric(minimum: Edge.Corner.Style? = nil) -> Self {
        Self(all: .concentric(minimum: minimum))
    }

    /// The style of `corner`.
    ///
    /// - Parameter corner: The corner.
    public subscript(corner: Edge.Corner) -> Edge.Corner.Style {
        switch corner {
        case .topLeading: topLeading
        case .topTrailing: topTrailing
        case .bottomLeading: bottomLeading
        case .bottomTrailing: bottomTrailing
        }
    }

    /// The radii these corners draw at, each concentric one with the
    /// container's corner on its side of `container`, lying `inset` inside it.
    func radii(container: RectangleCornerRadii?, inset: CGFloat) -> RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: topLeading.radius(container: container?.topLeading, inset: inset),
            bottomLeading: bottomLeading.radius(container: container?.bottomLeading, inset: inset),
            bottomTrailing: bottomTrailing.radius(container: container?.bottomTrailing, inset: inset),
            topTrailing: topTrailing.radius(container: container?.topTrailing, inset: inset))
    }
}

extension RoundedRectangularShapeCorners: Animatable {
    /// The four corners' radii.
    public struct AnimatableData: VectorArithmetic, Sendable {
        var radii: SIMD4<Double>

        /// No radius anywhere.
        public static var zero: Self { Self(radii: .zero) }

        /// The sum, corner by corner.
        public static func + (lhs: Self, rhs: Self) -> Self { Self(radii: lhs.radii + rhs.radii) }

        /// The difference, corner by corner.
        public static func - (lhs: Self, rhs: Self) -> Self { Self(radii: lhs.radii - rhs.radii) }

        /// Every radius scaled by `rhs`.
        public mutating func scale(by rhs: Double) { radii *= rhs }

        /// The sum of the radii's squares.
        public var magnitudeSquared: Double { (radii * radii).sum() }
    }

    /// The four radii, animated; which corners are concentric does not.
    public var animatableData: AnimatableData {
        get {
            AnimatableData(
                radii: SIMD4(
                    Double(topLeading.radius), Double(topTrailing.radius), Double(bottomLeading.radius),
                    Double(bottomTrailing.radius)))
        }
        set {
            topLeading = Edge.Corner.Style(radius: CGFloat(newValue.radii[0]), isConcentric: topLeading.isConcentric)
            topTrailing = Edge.Corner.Style(radius: CGFloat(newValue.radii[1]), isConcentric: topTrailing.isConcentric)
            bottomLeading = Edge.Corner.Style(
                radius: CGFloat(newValue.radii[2]), isConcentric: bottomLeading.isConcentric)
            bottomTrailing = Edge.Corner.Style(
                radius: CGFloat(newValue.radii[3]), isConcentric: bottomTrailing.isConcentric)
        }
    }
}

// MARK: - The protocol

/// A shape whose outline is a rectangle with rounded corners — mirrors
/// SwiftUI's `RoundedRectangularShape` (macOS 26). A container of one gives a
/// ``ConcentricRectangle`` inside it the corners to be concentric with.
nonisolated public protocol RoundedRectangularShape: InsettableShape {
    /// The corners' type.
    typealias Corners = RoundedRectangularShapeCorners

    /// The shape's corners in a frame of `size`, or `nil` where it cannot say
    /// without one.
    ///
    /// - Parameter size: The frame's size, in square units.
    /// - Returns: The corners.
    func corners(in size: CGSize?) -> Corners?
}

extension Rectangle: RoundedRectangularShape {
    /// Square corners.
    public func corners(in size: CGSize?) -> Corners? {
        .fixed(0)
    }
}

extension RoundedRectangle: RoundedRectangularShape {
    /// Every corner at the radius, held to half the shorter side where the
    /// size is known.
    public func corners(in size: CGSize?) -> Corners? {
        var radius = min(cornerSize.width, cornerSize.height) - insetAmount
        if let size { radius = min(radius, min(size.width, size.height) / 2) }
        return .fixed(max(0, radius))
    }
}

extension UnevenRoundedRectangle: RoundedRectangularShape {
    /// Each corner at its own radius.
    public func corners(in size: CGSize?) -> Corners? {
        let shrink = { (radius: CGFloat) in Edge.Corner.Style.fixed(max(0, radius - insetAmount)) }
        return Corners(
            topLeading: shrink(cornerRadii.topLeading), topTrailing: shrink(cornerRadii.topTrailing),
            bottomLeading: shrink(cornerRadii.bottomLeading), bottomTrailing: shrink(cornerRadii.bottomTrailing))
    }
}

extension Circle: RoundedRectangularShape {
    /// Half the shorter side, at every corner — `nil` with no size.
    public func corners(in size: CGSize?) -> Corners? {
        size.map { .fixed(max(0, min($0.width, $0.height) / 2 - insetAmount)) }
    }
}

extension Capsule: RoundedRectangularShape {
    /// Half the shorter side, at every corner — `nil` with no size.
    public func corners(in size: CGSize?) -> Corners? {
        size.map { .fixed(max(0, min($0.width, $0.height) / 2 - insetAmount)) }
    }
}

extension View {
    /// Sets the container shape to use for any container relative shape
    /// within this view — and the corners a ``ConcentricRectangle`` inside it
    /// is concentric with.
    ///
    /// - Parameter shape: The shape of this container.
    /// - Returns: The view, a container of that shape.
    public func containerShape(_ shape: some RoundedRectangularShape) -> some View {
        _ContainerShapeView(content: self, shape: ErasedInsettableShape(shape))
    }
}
