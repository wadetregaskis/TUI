//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RectangleCornerInsets.swift
//
//  SwiftUI's container corner insets: how far a container's corners reach
//  into the content it holds.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The inset sizes for the corners of a rectangle — mirrors SwiftUI's
/// `RectangleCornerInsets`, in cells.
public struct RectangleCornerInsets: Hashable, Sendable {
    /// The inset size of the top leading corner.
    public var topLeading: CellSize

    /// The inset size of the top trailing corner.
    public var topTrailing: CellSize

    /// The inset size of the bottom leading corner.
    public var bottomLeading: CellSize

    /// The inset size of the bottom trailing corner.
    public var bottomTrailing: CellSize

    /// Creates insets of zero at every corner.
    public init() {
        self.init(
            topLeading: CellSize(width: 0, height: 0), topTrailing: CellSize(width: 0, height: 0),
            bottomLeading: CellSize(width: 0, height: 0), bottomTrailing: CellSize(width: 0, height: 0))
    }

    /// Creates insets of the given sizes at each corner.
    ///
    /// - Parameters:
    ///   - topLeading: The inset of the top leading corner.
    ///   - topTrailing: The inset of the top trailing corner.
    ///   - bottomLeading: The inset of the bottom leading corner.
    ///   - bottomTrailing: The inset of the bottom trailing corner.
    public init(topLeading: CellSize, topTrailing: CellSize, bottomLeading: CellSize, bottomTrailing: CellSize) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }
}

extension GeometryProxy {
    /// The corner insets of the container view — mirrors SwiftUI's
    /// `containerCornerInsets`.
    ///
    /// Always zero, and truly so: a container's corner here is a glyph in its
    /// border's cell, never inside the content, and the app header and status
    /// bar are rows of their own rather than chrome over a window's corner.
    public var containerCornerInsets: RectangleCornerInsets {
        RectangleCornerInsets()
    }
}
