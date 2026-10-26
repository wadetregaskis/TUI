//  🖥️ TUI — A Terminal UI framework for Swift
//  ContentShapeKinds.swift
//
//  What a content shape is set for: the hit area, and the preview a drag
//  carries.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A kind for the content shape of a view — mirrors SwiftUI's
/// `ContentShapeKinds`.
///
/// The kinds a terminal has a use for:
///
/// - ``interaction``: the hit area. A click, a hover, a context menu or a drag
///   of the view answers only on the cells the shape keeps.
/// - ``dragPreview``: the preview a `.draggable` view carries, cut to the
///   shape; where the view can be grabbed is still its hit area.
///
/// SwiftUI's `focusEffect` and `accessibility` are omitted — TUI draws no
/// focus ring a shape could give its outline, and a screen reader reads a
/// terminal from its text, not from accessibility frames — and its
/// `contextMenuPreview` and `hoverEffect`, unavailable on macOS, are declined
/// with the effects they shape (refusal review O8). Each fails to compile
/// rather than shape nothing.
public struct ContentShapeKinds: OptionSet, Sendable {
    public var rawValue: Int

    /// Creates a set of kinds from its raw value.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The kind for hit-testing and accessibility: the cells where the view
    /// takes the pointer.
    public static let interaction = Self(rawValue: 1 << 0)

    /// The kind for drag and drop previews: the preview a drag of the view
    /// carries is cut to the shape. Where a drag can start is still the
    /// ``interaction`` shape.
    public static let dragPreview = Self(rawValue: 1 << 1)
}
