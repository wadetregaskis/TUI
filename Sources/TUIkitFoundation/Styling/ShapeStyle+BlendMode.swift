//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShapeStyle+BlendMode.swift
//
//  `ShapeStyle.blendMode(_:)`: a style whose paint is combined with what is
//  behind it, by whatever draws with it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension ShapeStyle {
    /// Returns a new style based on this one that blends with what is behind it
    /// using the specified mode. Mirrors SwiftUI's `ShapeStyle.blendMode(_:)`.
    ///
    /// Whatever draws with the style draws it as it would, and marks the cells it
    /// drew with the mode, to be combined with what is behind them where they land
    /// (``View/blendMode(_:)``, ``BlendMode``): a shape's fill or stroke, the
    /// letters of a `Text` under a `.foregroundStyle(_:)`, a `.background(_:)`'s
    /// field — the field alone, so the content in front of it is not blended.
    ///
    /// ```swift
    /// Text(match)
    ///     .background(.yellow.blendMode(.multiply))   // a highlighter
    /// ```
    ///
    /// A gradient background with a mode is drawn in cells, never as a picture: a
    /// picture has no mode to be combined with.
    ///
    /// - Parameter mode: The blend mode to apply.
    /// - Returns: A new shape style that uses the specified blend mode.
    public func blendMode(_ mode: BlendMode) -> some ShapeStyle {
        _BlendModeShapeStyle(base: self, mode: mode)
    }
}

/// ``ShapeStyle/blendMode(_:)``'s style: its base's paint, with the mode.
struct _BlendModeShapeStyle<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let mode: BlendMode

    typealias Resolved = Never

    func paint(in environment: EnvironmentValues) -> Paint {
        mode == .normal ? base.paint(in: environment) : .blended(base.paint(in: environment), mode)
    }
}
