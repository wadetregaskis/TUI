//  🖥️ TUI — A Terminal UI framework for Swift
//  Path+Interpolation.swift
//
//  One path part of the way to another: a TUI addition for morphing shapes.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

extension Path {
    /// This path moved `amount` of the way towards `other`, point by point.
    ///
    /// TUI-specific. SwiftUI's `Path` doesn't animate (its `animatableData` is
    /// empty, and TUI's matches), so a shape whose path changes jumps to the new
    /// one. To morph one outline into another, give a custom ``Shape`` a
    /// numeric `animatableData` for its progress and interpolate in
    /// ``Shape/path(in:)``:
    ///
    /// ```swift
    /// struct Morph: Shape {
    ///     var progress: Double
    ///     var animatableData: Double {
    ///         get { progress }
    ///         set { progress = newValue }
    ///     }
    ///
    ///     func path(in rect: CGRect) -> Path {
    ///         Rectangle().path(in: rect)
    ///             .interpolated(towards: Diamond().path(in: rect), amount: progress)
    ///     }
    /// }
    /// ```
    ///
    /// The name and the meaning of `amount` are ``VectorArithmetic``'s
    /// `interpolated(towards:amount:)`: 0 is this path, 1 is `other`, and
    /// `amount` is not clamped, so a spring that overshoots carries the points
    /// past `other` and back.
    ///
    /// **Matching structure.** Two paths interpolate when they have the same
    /// elements in the same order: a move with a move, a line with a line, a
    /// quadratic curve with a quadratic curve, a cubic with a cubic, a close
    /// with a close. Each point, control points included, moves in a straight
    /// line to its counterpart. Shapes built the same way match: a rectangle's
    /// path with another rectangle's, an ellipse's with another ellipse's, and
    /// a rectangle (a move, three lines and a close) with a diamond drawn the
    /// same way.
    ///
    /// **Different structure.** Paths that don't match are not resampled to
    /// make them: the result is this path while `amount` is below 0.5, and
    /// `other` from 0.5 on, so the shape swaps halfway rather than drawing
    /// something neither path describes. A rectangle (four lines) into a
    /// circle (four cubic curves) swaps; draw the rectangle as four straight
    /// cubic curves to morph it instead.
    ///
    /// - Parameters:
    ///   - other: The path to move towards.
    ///   - amount: How far: 0 is this path, 1 is `other`.
    /// - Returns: The path in between.
    public func interpolated(towards other: Path, amount: Double) -> Path {
        guard elements.count == other.elements.count else { return amount < 0.5 ? self : other }
        var result = Path()
        for (from, to) in zip(elements, other.elements) {
            guard let element = Self.interpolate(from, to, amount) else { return amount < 0.5 ? self : other }
            result.append(element)
        }
        return result
    }

    /// `from` moved `amount` of the way to `to`, or `nil` when they are
    /// different kinds of element.
    private static func interpolate(_ from: Element, _ to: Element, _ amount: Double) -> Element? {
        // Weighted at both ends rather than `start + (end - start) * amount`,
        // so 0 is exactly `start` and 1 exactly `end`, with no rounding left.
        let (kept, taken) = (CGFloat(1 - amount), CGFloat(amount))
        func mix(_ start: CGPoint, _ end: CGPoint) -> CGPoint {
            CGPoint(x: start.x * kept + end.x * taken, y: start.y * kept + end.y * taken)
        }
        switch (from, to) {
        case (.move(let start), .move(let end)):
            return .move(to: mix(start, end))
        case (.line(let start), .line(let end)):
            return .line(to: mix(start, end))
        case (.quadCurve(let start, let startControl), .quadCurve(let end, let endControl)):
            return .quadCurve(to: mix(start, end), control: mix(startControl, endControl))
        case (.curve(let start, let startFirst, let startSecond), .curve(let end, let endFirst, let endSecond)):
            return .curve(to: mix(start, end), control1: mix(startFirst, endFirst), control2: mix(startSecond, endSecond))
        case (.closeSubpath, .closeSubpath):
            return .closeSubpath
        default:
            return nil
        }
    }
}
