//  🖥️ TUI — A Terminal UI framework for Swift
//  UnitCurve+UnitPoint.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension UnitCurve {
    /// Creates a new curve using bezier control points.
    ///
    /// The x components of the control points are clamped to the range [0,1]
    /// when the curve is evaluated.
    ///
    /// Declared here rather than with the curve because `UnitPoint` is.
    ///
    /// - Parameters:
    ///   - startControlPoint: The cubic Bézier control point associated with
    ///     the curve's start point at (0, 0). The tangent vector from the start
    ///     point to its control point defines the initial velocity of the
    ///     timing function.
    ///   - endControlPoint: The cubic Bézier control point associated with the
    ///     curve's end point at (1, 1). The tangent vector from the end point to
    ///     its control point defines the final velocity of the timing function.
    public static func bezier(
        startControlPoint: UnitPoint, endControlPoint: UnitPoint
    ) -> UnitCurve {
        .bezier(
            p1x: startControlPoint.x, p1y: startControlPoint.y,
            p2x: endControlPoint.x, p2y: endControlPoint.y)
    }
}
