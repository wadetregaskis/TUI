//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RoundedCornerStyle.swift
//
//  How a rounded rectangle's corners curve, and how far each one does.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - RoundedCornerStyle

/// Defines the shape of a rounded rectangle's corners — mirrors SwiftUI's
/// `RoundedCornerStyle`.
///
/// Both styles reach the same edges at the same distance from the corner along
/// the box's sides as SwiftUI's paths do (measured: `RoundedRectangle`'s path
/// in a 20 × 10 rectangle, `Tools/SwiftUIProbes`-style probe in the session
/// notes, W1). In a terminal the two differ by less than a sub-cell unit at any
/// radius a cell grid can show, so a box drawn in lines rounds its corners the
/// same way — `╭` — whichever style is asked for: that is quantisation, not a
/// dropped request.
public enum RoundedCornerStyle: Hashable, Sendable {
    /// Quarter-circle corners.
    case circular

    /// Corners that ease into their sides — Apple's "continuous" curve, which
    /// starts half as far again from the corner as a circle of the same radius.
    case continuous
}

// MARK: - RectangleCornerRadii

/// Describes the corner radius values of a rounded rectangle with uneven
/// corners — mirrors SwiftUI's `RectangleCornerRadii`.
///
/// The radii are in the shape's own unit — columns, by the reading
/// ``Shape/path(in:)`` documents — so `RectangleCornerRadii(topLeading: 2)` is a
/// corner two columns across and one row down, round on screen.
public struct RectangleCornerRadii: Equatable, Sendable {
    /// The radius of the top-leading corner.
    public var topLeading: CGFloat

    /// The radius of the bottom-leading corner.
    public var bottomLeading: CGFloat

    /// The radius of the bottom-trailing corner.
    public var bottomTrailing: CGFloat

    /// The radius of the top-trailing corner.
    public var topTrailing: CGFloat

    /// Creates a new set of corner radii for a rounded rectangle with uneven
    /// corners.
    ///
    /// - Parameters:
    ///   - topLeading: The radius of the top-leading corner.
    ///   - bottomLeading: The radius of the bottom-leading corner.
    ///   - bottomTrailing: The radius of the bottom-trailing corner.
    ///   - topTrailing: The radius of the top-trailing corner.
    public init(
        topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0
    ) {
        self.topLeading = topLeading
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
        self.topTrailing = topTrailing
    }
}

extension RectangleCornerRadii: Animatable {
    /// The top corners, then the bottom ones — leading before trailing in each.
    public typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>

    /// The four radii, animated together.
    public var animatableData: AnimatableData {
        get {
            AnimatablePair(AnimatablePair(topLeading, topTrailing), AnimatablePair(bottomLeading, bottomTrailing))
        }
        set {
            topLeading = newValue.first.first
            topTrailing = newValue.first.second
            bottomLeading = newValue.second.first
            bottomTrailing = newValue.second.second
        }
    }
}
