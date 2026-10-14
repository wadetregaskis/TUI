//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UnitCurve.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// A function defined by a two-dimensional curve that maps an input progress
/// in the range [0,1] to an output progress that is also in the range [0,1].
/// By changing the shape of the curve, the effective speed of an animation or
/// other interpolation can be changed.
///
/// The horizontal (x) axis defines the input progress: a single input progress
/// value in the range [0,1] must be provided when evaluating a curve.
///
/// The vertical (y) axis maps to the output progress: when a curve is
/// evaluated, the y component of the point that intersects the input progress
/// is returned.
///
/// The Bézier curves are evaluated by the same solver as an ``Animation``'s
/// timing curve, so `Animation.timingCurve(.easeIn, duration: d)` and
/// `Animation.easeIn(duration: d)` move identically.
public struct UnitCurve: Hashable, Sendable {
    /// What the curve is.
    enum Function: Hashable, Sendable {
        /// `y = x`. Not a Bézier, as in SwiftUI (measured): a Bézier through
        /// the diagonal draws the same line and is a different curve.
        case linear
        /// A cubic Bézier through `(0, 0)`, the two control points, `(1, 1)`.
        case bezier(p1x: Double, p1y: Double, p2x: Double, p2y: Double)
        /// A quarter or two of a unit circle.
        case circular(CircularCurve)
    }

    let function: Function

    init(_ function: Function) {
        self.function = function
    }

    /// A cubic Bézier through `(0, 0)`, `(p1x, p1y)`, `(p2x, p2y)` and
    /// `(1, 1)`: the coordinates of ``bezier(startControlPoint:endControlPoint:)``,
    /// which is declared beside `UnitPoint`.
    package static func bezier(p1x: Double, p1y: Double, p2x: Double, p2y: Double) -> Self {
        Self(.bezier(p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y))
    }

    /// The control points of a Bézier curve, its x coordinates clamped to
    /// [0,1] as SwiftUI documents they are when the curve is evaluated.
    private static func clampedBezier(_ p1x: Double, _ p2x: Double) -> (Double, Double) {
        (min(1, max(0, p1x)), min(1, max(0, p2x)))
    }

    /// Returns the output value (y component) of the curve at the given time.
    ///
    /// - Parameter progress: The input progress (x component). The provided
    ///   value is clamped to the range [0,1].
    /// - Returns: The output value (y component) of the curve at the given
    ///   progress.
    public func value(at progress: Double) -> Double {
        let x = min(1, max(0, progress))
        switch function {
        case .linear:
            return x
        case .bezier(let p1x, let p1y, let p2x, let p2y):
            let (c1x, c2x) = Self.clampedBezier(p1x, p2x)
            return AnimationCurve.bezierValue(atX: x, p1x: c1x, p1y: p1y, p2x: c2x, p2y: p2y)
        case .circular(let curve):
            return curve.value(at: x)
        }
    }

    /// Returns the rate of change (first derivative) of the output value of
    /// the curve at the given time.
    ///
    /// - Parameter progress: The input progress (x component). The provided
    ///   value is clamped to the range [0,1].
    /// - Returns: The velocity of the output value (y component) of the curve
    ///   at the given time. Where a circular curve is vertical — its end, or
    ///   its middle for the two-part ones — that is infinite.
    public func velocity(at progress: Double) -> Double {
        let x = min(1, max(0, progress))
        switch function {
        case .linear:
            return 1
        case .bezier(let p1x, let p1y, let p2x, let p2y):
            let (c1x, c2x) = Self.clampedBezier(p1x, p2x)
            return AnimationCurve.bezierVelocity(atX: x, p1x: c1x, p1y: p1y, p2x: c2x, p2y: p2y)
        case .circular(let curve):
            return curve.velocity(at: x)
        }
    }

    /// Returns a copy of the curve with its x and y components swapped.
    ///
    /// The inverse can be used to solve a curve in reverse: given a known
    /// output (y) value, the corresponding input (x) value can be found by
    /// using `inverse`:
    ///
    /// ```swift
    /// let curve = UnitCurve.easeInOut
    /// // The input time for which an easeInOut curve returns 0.6.
    /// let inputTime = curve.inverse.value(at: 0.6)
    /// ```
    ///
    /// The inverse of `circularEaseInOut` is the curve swapped as this says —
    /// fast at the ends and level in the middle — where SwiftUI, measured,
    /// answers `circularEaseInOut` itself.
    public var inverse: Self {
        switch function {
        case .linear:
            self
        case .bezier(let p1x, let p1y, let p2x, let p2y):
            Self(.bezier(p1x: p1y, p1y: p1x, p2x: p2y, p2y: p2x))
        case .circular(let curve):
            Self(.circular(curve.inverse))
        }
    }

    /// A linear curve.
    ///
    /// As the linear curve is a straight line from (0, 0) to (1, 1), the
    /// output progress is always equal to the input progress, and the velocity
    /// is always equal to 1.0.
    public static let linear = Self(.linear)

    /// A bezier curve that starts out slowly, then speeds up as it finishes.
    ///
    /// The start and end control points are located at (x: 0.42, y: 0) and
    /// (x: 1, y: 1).
    public static let easeIn = Self.bezier(p1x: 0.42, p1y: 0, p2x: 1, p2y: 1)

    /// A bezier curve that starts out quickly, then slows down as it approaches
    /// the end.
    ///
    /// The start and end control points are located at (x: 0, y: 0) and
    /// (x: 0.58, y: 1).
    public static let easeOut = Self.bezier(p1x: 0, p1y: 0, p2x: 0.58, p2y: 1)

    /// A bezier curve that starts out slowly, speeds up over the middle, then
    /// slows down again as it approaches the end.
    ///
    /// The start and end control points are located at (x: 0.42, y: 0) and
    /// (x: 0.58, y: 1).
    public static let easeInOut = Self.bezier(p1x: 0.42, p1y: 0, p2x: 0.58, p2y: 1)

    /// A curve that starts out slowly, then speeds up as it finishes.
    ///
    /// The shape of the curve is equal to the fourth (bottom right) quadrant
    /// of a unit circle.
    public static let circularEaseIn = Self(.circular(.easeIn))

    /// A circular curve that starts out quickly, then slows down as it
    /// approaches the end.
    ///
    /// The shape of the curve is equal to the second (top left) quadrant of a
    /// unit circle.
    public static let circularEaseOut = Self(.circular(.easeOut))

    /// A circular curve that starts out slowly, speeds up over the middle,
    /// then slows down again as it approaches the end.
    ///
    /// The shape of the curve is defined by a piecewise combination of
    /// `circularEaseIn` and `circularEaseOut`.
    public static let circularEaseInOut = Self(.circular(.easeInOut))
}

/// The circular curves: quarters of a unit circle, alone or in two halves.
enum CircularCurve: Hashable, Sendable {
    /// `1 − √(1 − x²)`: the bottom-right quadrant.
    case easeIn
    /// `√(1 − (1 − x)²)`: the top-left quadrant, `easeIn`'s inverse.
    case easeOut
    /// `easeIn` then `easeOut`, each over half the input.
    case easeInOut
    /// `easeOut` then `easeIn`: `easeInOut`'s inverse, which has no name.
    case easeOutIn

    /// The curve's `y` at `x`, for `x` in [0,1].
    func value(at x: Double) -> Double {
        switch self {
        case .easeIn: Self.quarterIn(x)
        case .easeOut: Self.quarterOut(x)
        case .easeInOut: x < 0.5 ? Self.quarterIn(2 * x) / 2 : 0.5 + Self.quarterOut(2 * x - 1) / 2
        case .easeOutIn: x < 0.5 ? Self.quarterOut(2 * x) / 2 : 0.5 + Self.quarterIn(2 * x - 1) / 2
        }
    }

    /// The curve's slope at `x`, for `x` in [0,1]. Halving both axes leaves a
    /// half's slope as the quarter's.
    func velocity(at x: Double) -> Double {
        switch self {
        case .easeIn: Self.slopeIn(x)
        case .easeOut: Self.slopeOut(x)
        case .easeInOut: Self.slope(x < 0.5 ? .easeIn : .easeOut, at: x < 0.5 ? 2 * x : 2 * x - 1)
        case .easeOutIn: Self.slope(x < 0.5 ? .easeOut : .easeIn, at: x < 0.5 ? 2 * x : 2 * x - 1)
        }
    }

    /// A quarter's slope at `x`.
    private static func slope(_ quarter: Self, at x: Double) -> Double {
        quarter == .easeIn ? slopeIn(x) : slopeOut(x)
    }

    /// The curve with x and y swapped.
    var inverse: Self {
        switch self {
        case .easeIn: .easeOut
        case .easeOut: .easeIn
        case .easeInOut: .easeOutIn
        case .easeOutIn: .easeInOut
        }
    }

    private static func quarterIn(_ x: Double) -> Double { 1 - (1 - x * x).squareRoot() }
    private static func quarterOut(_ x: Double) -> Double { (1 - (1 - x) * (1 - x)).squareRoot() }
    private static func slopeIn(_ x: Double) -> Double { x / (1 - x * x).squareRoot() }
    private static func slopeOut(_ x: Double) -> Double { (1 - x) / (1 - (1 - x) * (1 - x)).squareRoot() }
}

extension Animation {
    /// Creates a new animation with speed controlled by the given curve.
    ///
    /// - Parameters:
    ///   - curve: A curve that describes the speed of the animation over its
    ///     duration.
    ///   - duration: The duration of the animation, in seconds.
    public static func timingCurve(_ curve: UnitCurve, duration: TimeInterval) -> Animation {
        switch curve.function {
        case .linear:
            linear(duration: duration)
        case .bezier(let p1x, let p1y, let p2x, let p2y):
            timingCurve(min(1, max(0, p1x)), p1y, min(1, max(0, p2x)), p2y, duration: duration)
        case .circular(let circular):
            Animation(curve: .circular(circular), passDuration: duration)
        }
    }
}
