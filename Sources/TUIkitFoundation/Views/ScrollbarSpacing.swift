//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollbarSpacing.swift
//
//  The cells a list or a table keeps between its rows' content and its
//  vertical scrollbar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

private struct ScrollbarSpacingKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The cells a ``List`` or a ``Table`` in this subtree keeps between its
    /// rows' content and its vertical scrollbar, or `nil` for theirs: one.
    ///
    /// Set through ``View/scrollbarSpacing(_:)``.
    public internal(set) var scrollbarSpacing: Int? {
        get { self[ScrollbarSpacingKey.self] }
        set { self[ScrollbarSpacingKey.self] = newValue }
    }

    /// The cells a list's or a table's rows keep clear before its vertical
    /// scrollbar: none without a bar, else ``scrollbarSpacing`` — one unless
    /// stated, and never negative.
    package func rowScrollbarSpacing(showsBar: Bool) -> Int {
        showsBar ? max(0, scrollbarSpacing ?? 1) : 0
    }
}

extension View {
    /// Sets how many cells a ``List`` or a ``Table`` within this view keeps
    /// between its rows' content and its vertical scrollbar.
    ///
    /// TUI-specific. A list's or a table's text otherwise runs right up to the
    /// bar, one cell from a glyph that is itself a column of ink, and reads as
    /// part of it — so by default they keep one cell clear. The rows' own fill
    /// (a stripe, a selection, the focused row's breath) runs on across those
    /// cells to the bar: it is only the content that stops short. `0` puts the
    /// content against the bar; `2` or `3` give it more room. Only a drawn bar
    /// takes any: with none, the rows have the width it would have had.
    ///
    /// ```swift
    /// Table(files) { … }
    ///     .scrollIndicators(.visible)
    ///     .scrollbarSpacing(0)   // columns right up to the bar
    /// ```
    ///
    /// - Parameter cells: The cells between the content and the bar.
    /// A list lays its rows out before it knows whether they overflow, so it
    /// predicts the bar from its last frame; on the frame a bar first appears
    /// (or goes) its rows are laid out again on the next.
    ///
    /// - Returns: A view whose lists and tables keep that spacing.
    public func scrollbarSpacing(_ cells: Int) -> some View {
        environment(\.scrollbarSpacing, max(0, cells))
    }
}
