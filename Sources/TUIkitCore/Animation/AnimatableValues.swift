//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatableValues.swift
//
//  SwiftUI's `AnimatableValues`: any number of animatable values animated as
//  one, the variadic form of `AnimatablePair`.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A tuple of animatable values — mirrors SwiftUI's `AnimatableValues`.
///
/// The variadic replacement for nested ``AnimatablePair``s: a type with three
/// animatable properties gives `AnimatableValues(x, y, opacity)` as its
/// `animatableData` rather than a pair of a pair.
///
/// ```swift
/// var animatableData: AnimatableValues<Double, Double, Double> {
///     get { AnimatableValues(x, y, opacity) }
///     set { (x, y, opacity) = newValue.value }
/// }
/// ```
@frozen
public struct AnimatableValues<each Value: VectorArithmetic>: VectorArithmetic {
    /// The tuple of values.
    public var value: (repeat each Value)

    /// Creates a tuple of animatable values.
    ///
    /// - Parameter value: The values.
    public init(_ value: repeat each Value) {
        self.value = (repeat each value)
    }

    public static var zero: Self {
        Self(repeat (each Value).zero)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(repeat (each lhs.value) + (each rhs.value))
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        Self(repeat (each lhs.value) - (each rhs.value))
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout Self, rhs: Self) {
        lhs = lhs - rhs
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // A guard rather than a `where`: pack iteration takes no clause.
        for (left, right) in repeat (each lhs.value, each rhs.value) {
            guard left == right else { return false }
        }
        return true
    }

    public mutating func scale(by rhs: Double) {
        value = (repeat (each value).scaled(by: rhs))
    }

    public var magnitudeSquared: Double {
        var total = 0.0
        for element in repeat each value {
            total += element.magnitudeSquared
        }
        return total
    }
}

extension AnimatableValues: Sendable where repeat each Value: Sendable {}
