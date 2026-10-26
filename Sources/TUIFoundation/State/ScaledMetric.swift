//  🖥️ TUI — A Terminal UI framework for Swift
//  ScaledMetric.swift
//
//  SwiftUI's `@ScaledMetric`: a dimension that scales with the user's text
//  size — which, on macOS and in a terminal, it does not.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A dynamic property that scales a numeric value — mirrors SwiftUI's
/// `ScaledMetric`.
///
/// On iOS the value grows with the user's Dynamic Type size. On macOS it does
/// not: measured on macOS 15, a `@ScaledMetric` of 10 reads 10 at every
/// `\.dynamicTypeSize` from `.xSmall` to `.accessibility5`, written or not, for
/// any text style. TUI matches that, and a terminal gives the same answer
/// for its own reason: the user sets the text size in the emulator, and a
/// dimension in cells grows with the font already.
///
/// `Value` may be any `Numeric`, where SwiftUI asks for `BinaryFloatingPoint`,
/// so a metric can be the `Int` cell counts TUI's frames and padding take:
///
/// ```swift
/// @ScaledMetric(relativeTo: .body) var gutter = 2
/// ```
@propertyWrapper
public struct ScaledMetric<Value: Numeric & Sendable>: Sendable {
    /// The value, unscaled.
    public let wrappedValue: Value

    /// Creates the scaled metric with an unscaled value, scaled relative to
    /// the body text style.
    ///
    /// - Parameter wrappedValue: The base value.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// Creates the scaled metric with an unscaled value, scaled relative to a
    /// text style.
    ///
    /// - Parameters:
    ///   - wrappedValue: The base value.
    ///   - textStyle: The text style the value would scale with.
    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) {
        self.wrappedValue = wrappedValue
    }
}
