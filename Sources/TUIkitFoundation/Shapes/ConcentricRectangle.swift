//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ConcentricRectangle.swift
//
//  A rectangle whose corners follow its container's.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// A rectangle whose corners are concentric with its container's — mirrors
/// SwiftUI's `ConcentricRectangle` (macOS 26).
///
/// A corner styled ``Edge/Corner/Style/concentric`` takes the radius of the
/// container's corner on its side — the container set by
/// ``View/containerShape(_:)-(RoundedRectangularShape)`` — less how far inside
/// the container this shape lies, so nested rounded panels stay concentric; and
/// a corner inset as far as the container's radius is square, `┌`. A fixed
/// corner keeps its radius. With no container, a concentric corner is its
/// minimum, or square.
///
/// Drawn as a rectangle of the rounded family is: in box glyphs, a corner per
/// corner. `isUniform` makes every corner the smallest of the four (SwiftUI's
/// reading is not measured here: its macOS 26 API is read from the SDK, and this
/// Mac runs macOS 15).
nonisolated public struct ConcentricRectangle: Shape {
    /// The corners.
    var corners: RoundedRectangularShapeCorners
    /// Whether every corner takes the smallest radius of the four.
    var isUniform: Bool

    /// A rectangle every corner of which is concentric with its container's.
    public init() {
        self.init(corners: .concentric)
    }

    /// A rectangle every corner of which is styled `corners`.
    ///
    /// - Parameters:
    ///   - corners: The style of every corner.
    ///   - isUniform: Whether every corner takes the smallest radius of the four.
    public init(corners: Edge.Corner.Style, isUniform: Bool = false) {
        self.corners = RoundedRectangularShapeCorners(all: corners)
        self.isUniform = isUniform
    }

    /// A rectangle styled corner by corner.
    ///
    /// - Parameters:
    ///   - topLeadingCorner: The top-leading corner.
    ///   - topTrailingCorner: The top-trailing corner.
    ///   - bottomLeadingCorner: The bottom-leading corner.
    ///   - bottomTrailingCorner: The bottom-trailing corner.
    public init(
        topLeadingCorner: Edge.Corner.Style = .concentric, topTrailingCorner: Edge.Corner.Style = .concentric,
        bottomLeadingCorner: Edge.Corner.Style = .concentric, bottomTrailingCorner: Edge.Corner.Style = .concentric
    ) {
        self.corners = RoundedRectangularShapeCorners(
            topLeading: topLeadingCorner, topTrailing: topTrailingCorner, bottomLeading: bottomLeadingCorner,
            bottomTrailing: bottomTrailingCorner)
        self.isUniform = false
    }

    /// A rectangle whose top corners are styled alike, and its bottom ones.
    public init(uniformTopCorners: Edge.Corner.Style = .concentric, uniformBottomCorners: Edge.Corner.Style = .concentric) {
        self.init(
            topLeadingCorner: uniformTopCorners, topTrailingCorner: uniformTopCorners,
            bottomLeadingCorner: uniformBottomCorners, bottomTrailingCorner: uniformBottomCorners)
    }

    /// A rectangle whose leading corners are styled alike, and its trailing
    /// ones.
    public init(
        uniformLeadingCorners: Edge.Corner.Style = .concentric, uniformTrailingCorners: Edge.Corner.Style = .concentric
    ) {
        self.init(
            topLeadingCorner: uniformLeadingCorners, topTrailingCorner: uniformTrailingCorners,
            bottomLeadingCorner: uniformLeadingCorners, bottomTrailingCorner: uniformTrailingCorners)
    }

    /// A rectangle whose top corners are styled alike, and its bottom ones each.
    public init(
        uniformTopCorners: Edge.Corner.Style = .concentric, bottomLeadingCorner: Edge.Corner.Style = .concentric,
        bottomTrailingCorner: Edge.Corner.Style = .concentric
    ) {
        self.init(
            topLeadingCorner: uniformTopCorners, topTrailingCorner: uniformTopCorners,
            bottomLeadingCorner: bottomLeadingCorner, bottomTrailingCorner: bottomTrailingCorner)
    }

    /// A rectangle whose bottom corners are styled alike, and its top ones each.
    public init(
        uniformBottomCorners: Edge.Corner.Style = .concentric, topLeadingCorner: Edge.Corner.Style = .concentric,
        topTrailingCorner: Edge.Corner.Style = .concentric
    ) {
        self.init(
            topLeadingCorner: topLeadingCorner, topTrailingCorner: topTrailingCorner,
            bottomLeadingCorner: uniformBottomCorners, bottomTrailingCorner: uniformBottomCorners)
    }

    /// A rectangle whose leading corners are styled alike, and its trailing
    /// ones each.
    public init(
        uniformLeadingCorners: Edge.Corner.Style = .concentric, topTrailingCorner: Edge.Corner.Style = .concentric,
        bottomTrailingCorner: Edge.Corner.Style = .concentric
    ) {
        self.init(
            topLeadingCorner: uniformLeadingCorners, topTrailingCorner: topTrailingCorner,
            bottomLeadingCorner: uniformLeadingCorners, bottomTrailingCorner: bottomTrailingCorner)
    }

    /// A rectangle whose trailing corners are styled alike, and its leading
    /// ones each.
    public init(
        uniformTrailingCorners: Edge.Corner.Style = .concentric, topLeadingCorner: Edge.Corner.Style = .concentric,
        bottomLeadingCorner: Edge.Corner.Style = .concentric
    ) {
        self.init(
            topLeadingCorner: topLeadingCorner, topTrailingCorner: uniformTrailingCorners,
            bottomLeadingCorner: bottomLeadingCorner, bottomTrailingCorner: uniformTrailingCorners)
    }

    /// With no container to be concentric with: each concentric corner at its
    /// minimum.
    public func path(in rect: CGRect) -> Path {
        path(in: rect, container: nil, inset: 0)
    }

    /// The radii in `rect`, concentric with `container`'s corners from `inset`
    /// inside it.
    func radii(container: RectangleCornerRadii?, inset: CGFloat) -> RectangleCornerRadii {
        let radii = corners.radii(container: container, inset: inset)
        guard isUniform else { return radii }
        let smallest = min(radii.topLeading, radii.topTrailing, radii.bottomLeading, radii.bottomTrailing)
        return RectangleCornerRadii(topLeading: smallest, bottomLeading: smallest, bottomTrailing: smallest, topTrailing: smallest)
    }

    /// The outline, its concentric corners resolved against `container`.
    func path(in rect: CGRect, container: RectangleCornerRadii?, inset: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadii: radii(container: container, inset: inset), style: .continuous)
    }
}

extension ConcentricRectangle: Animatable {
    /// The corners' radii.
    public struct AnimatableData: Equatable, VectorArithmetic, Sendable {
        var corners: RoundedRectangularShapeCorners.AnimatableData

        /// No radius anywhere.
        public static var zero: Self { Self(corners: .zero) }

        /// The sum, corner by corner.
        public static func + (lhs: Self, rhs: Self) -> Self { Self(corners: lhs.corners + rhs.corners) }

        /// The difference, corner by corner.
        public static func - (lhs: Self, rhs: Self) -> Self { Self(corners: lhs.corners - rhs.corners) }

        /// Every radius scaled by `rhs`.
        public mutating func scale(by rhs: Double) { corners.scale(by: rhs) }

        /// The sum of the radii's squares.
        public var magnitudeSquared: Double { corners.magnitudeSquared }
    }

    /// The corners' radii, animated.
    @MainActor public var animatableData: AnimatableData {
        get { AnimatableData(corners: corners.animatableData) }
        set { corners.animatableData = newValue.corners }
    }
}

extension ConcentricRectangle: EnvironmentResolvedShape {
    /// Its corners resolved against the container's, from as far inside it as
    /// it lies: an uneven rounded rectangle, drawn in box glyphs.
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        let aspect = context.environment.imageCellAspect
        guard let container = context.environment.containerShapeContext else {
            return UnevenRoundedRectangle(cornerRadii: radii(container: nil, inset: 0))
        }
        let inset = container.distance(ofViewAt: context.geometryOrigin, columns: columns, rows: rows, aspect: aspect)
        let containerRadii = container.shape.cornerRadii(
            in: CGSize(width: CGFloat(container.columns), height: CGFloat(container.rows) * CGFloat(aspect)))
        return UnevenRoundedRectangle(cornerRadii: radii(container: containerRadii, inset: inset))
    }
}

extension Shape where Self == ConcentricRectangle {
    /// A concentric rectangle every corner of which is styled `corners`.
    public static func rect(corners: Edge.Corner.Style, isUniform: Bool = false) -> Self {
        .init(corners: corners, isUniform: isUniform)
    }

    /// A concentric rectangle styled corner by corner.
    public static func rect(
        topLeadingCorner: Edge.Corner.Style, topTrailingCorner: Edge.Corner.Style,
        bottomLeadingCorner: Edge.Corner.Style, bottomTrailingCorner: Edge.Corner.Style
    ) -> Self {
        .init(
            topLeadingCorner: topLeadingCorner, topTrailingCorner: topTrailingCorner,
            bottomLeadingCorner: bottomLeadingCorner, bottomTrailingCorner: bottomTrailingCorner)
    }

    /// A concentric rectangle whose top corners are alike, and its bottom ones.
    public static func rect(uniformTopCorners: Edge.Corner.Style, uniformBottomCorners: Edge.Corner.Style) -> Self {
        .init(uniformTopCorners: uniformTopCorners, uniformBottomCorners: uniformBottomCorners)
    }

    /// A concentric rectangle whose leading corners are alike, and its trailing
    /// ones.
    public static func rect(uniformLeadingCorners: Edge.Corner.Style, uniformTrailingCorners: Edge.Corner.Style) -> Self {
        .init(uniformLeadingCorners: uniformLeadingCorners, uniformTrailingCorners: uniformTrailingCorners)
    }

    /// A concentric rectangle whose top corners are alike, and its bottom ones
    /// each.
    public static func rect(
        uniformTopCorners: Edge.Corner.Style, bottomLeadingCorner: Edge.Corner.Style,
        bottomTrailingCorner: Edge.Corner.Style
    ) -> Self {
        .init(
            uniformTopCorners: uniformTopCorners, bottomLeadingCorner: bottomLeadingCorner,
            bottomTrailingCorner: bottomTrailingCorner)
    }

    /// A concentric rectangle whose bottom corners are alike, and its top ones
    /// each.
    public static func rect(
        uniformBottomCorners: Edge.Corner.Style, topLeadingCorner: Edge.Corner.Style,
        topTrailingCorner: Edge.Corner.Style
    ) -> Self {
        .init(
            uniformBottomCorners: uniformBottomCorners, topLeadingCorner: topLeadingCorner,
            topTrailingCorner: topTrailingCorner)
    }

    /// A concentric rectangle whose leading corners are alike, and its
    /// trailing ones each.
    public static func rect(
        uniformLeadingCorners: Edge.Corner.Style, topTrailingCorner: Edge.Corner.Style,
        bottomTrailingCorner: Edge.Corner.Style
    ) -> Self {
        .init(
            uniformLeadingCorners: uniformLeadingCorners, topTrailingCorner: topTrailingCorner,
            bottomTrailingCorner: bottomTrailingCorner)
    }

    /// A concentric rectangle whose trailing corners are alike, and its
    /// leading ones each.
    public static func rect(
        uniformTrailingCorners: Edge.Corner.Style, topLeadingCorner: Edge.Corner.Style,
        bottomLeadingCorner: Edge.Corner.Style
    ) -> Self {
        .init(
            uniformTrailingCorners: uniformTrailingCorners, topLeadingCorner: topLeadingCorner,
            bottomLeadingCorner: bottomLeadingCorner)
    }
}
