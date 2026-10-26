//  🖥️ TUI — A Terminal UI framework for Swift
//  FillStyle.swift
//
//  How a shape's inside is decided and drawn, and how its outline is traced.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

// MARK: - FillStyle

/// A style for rasterizing vector shapes — mirrors SwiftUI's `FillStyle`.
///
/// A shape drawn by the rasterizer covers each cell's halves by some fraction,
/// and that fraction is drawn as alpha: the edge of a circle blends into what
/// is behind it, which is antialiasing on a cell grid. Without antialiasing the
/// fraction is held to whole — a half that is at least half covered is drawn,
/// the rest is not. A shape drawn in box-drawing glyphs (a rectangle's lines)
/// has no fractions to draw either way.
public struct FillStyle: Equatable, Sendable {
    /// A Boolean value that indicates whether to use the even-odd rule when
    /// rendering a shape. When it is `false`, the non-zero winding rule
    /// decides what is inside.
    public var isEOFilled: Bool

    /// A Boolean value that indicates whether to apply antialiasing to the
    /// edges of a shape: whether a partly covered half cell is drawn at its
    /// coverage, or held to whole at a half.
    public var isAntialiased: Bool

    /// Creates a new fill style with the specified settings.
    ///
    /// - Parameters:
    ///   - eoFill: Whether to use the even-odd rule for rendering a shape;
    ///     `false` uses the non-zero winding number rule.
    ///   - antialiased: Whether to use antialiasing when rendering the edges of
    ///     a shape.
    public init(eoFill: Bool = false, antialiased: Bool = true) {
        isEOFilled = eoFill
        isAntialiased = antialiased
    }
}

// MARK: - StrokeStyle

/// The characteristics of a stroke that traces a path — mirrors SwiftUI's
/// `StrokeStyle`.
///
/// Lengths — the width, the dashes and the phase — are in a shape's unit:
/// columns across, and on the same scale down (``Shape/path(in:)``). So the
/// default `lineWidth: 1` is a line one column wide, half a row tall where it
/// runs along a row: the reading the shapes ruling (refusal review O0) gives
/// every literal length, as `.padding(1)` is one cell.
public struct StrokeStyle: Equatable, Sendable {
    /// The width of the stroked path.
    public var lineWidth: CGFloat

    /// The endpoint style of a line.
    public var lineCap: CGLineCap

    /// The join type of a line.
    public var lineJoin: CGLineJoin

    /// A threshold used to determine whether to use a bevel instead of a
    /// miter at a join: the length of the miter over the line's width.
    public var miterLimit: CGFloat

    /// The lengths of painted and unpainted segments used to make a dashed
    /// line.
    public var dash: [CGFloat]

    /// How far into the dash pattern the line starts.
    public var dashPhase: CGFloat

    /// Creates a new stroke style from the given components.
    ///
    /// - Parameters:
    ///   - lineWidth: The width of the segment.
    ///   - lineCap: The endpoint style of a segment.
    ///   - lineJoin: The join type of a segment.
    ///   - miterLimit: The threshold used to determine whether to use a bevel
    ///     instead of a miter at a join.
    ///   - dash: The lengths of painted and unpainted segments used to make a
    ///     dashed line.
    ///   - dashPhase: How far into the dash pattern the line starts.
    public init(
        lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 10,
        dash: [CGFloat] = [CGFloat](), dashPhase: CGFloat = 0
    ) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }
}

extension StrokeStyle: Animatable {
    /// The width, then the miter limit and the dash phase.
    public typealias AnimatableData = AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>

    /// The stroke's continuous lengths: its width, its miter limit and its
    /// dash phase. The dash pattern itself does not animate.
    public var animatableData: AnimatableData {
        get { AnimatablePair(lineWidth, AnimatablePair(miterLimit, dashPhase)) }
        set {
            lineWidth = newValue.first
            miterLimit = newValue.second.first
            dashPhase = newValue.second.second
        }
    }
}
