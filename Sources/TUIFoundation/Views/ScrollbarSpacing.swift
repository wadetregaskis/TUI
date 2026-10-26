//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollbarSpacing.swift
//
//  The cells a list or a table keeps between its rows' content and its
//  vertical scrollbar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

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

// MARK: - Width

private struct ScrollbarWidthKey: EnvironmentKey {
    static let defaultValue = 1
}

extension EnvironmentValues {
    /// How many cells wide the vertical scrollbars in this subtree are: one, or
    /// two for a double-width bar. Set through ``View/scrollbarWidth(_:)``.
    public internal(set) var scrollbarWidth: Int {
        get { self[ScrollbarWidthKey.self] }
        set { self[ScrollbarWidthKey.self] = newValue }
    }
}

/// Whether the terminal draws the corner triangles edge to edge; `true` where
/// nothing has said otherwise (headless, tests), the owner's default (FB6).
private struct CornerTrianglesFillTheCellKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the terminal draws the corner triangles `◢ ◣ ◤ ◥` edge to edge
    /// in their cells, so that a pair reads as one arrow across two cells. Set
    /// by the run loop from `TerminalHost`, per tmux client where there are
    /// any; read by a double-width scrollbar for its end arrows.
    package var cornerTrianglesFillTheCell: Bool {
        get { self[CornerTrianglesFillTheCellKey.self] }
        set { self[CornerTrianglesFillTheCellKey.self] = newValue }
    }
}

extension View {
    /// Draws the vertical scrollbars within this view `cells` wide: `1`, the
    /// default, or `2` for a double-width bar.
    ///
    /// TUI-specific. A bar one cell wide is a thin target for a pointer, and a
    /// thin line beside a page of text; two cells is easier to hit and to see,
    /// for the column it costs. Every cell of a line of the thumb and track draws
    /// the same glyph, the thumb's eighths side by side. Each end arrow is one
    /// triangle across both cells (`◢◣`, `◥◤`) where the terminal draws those
    /// halves edge to edge, and two arrows (`▲▲`, `▼▼`) where it does not —
    /// Apple Terminal and Warp. The whole width takes the pointer. A ``ScrollView``, a
    /// ``List``, a ``Table`` and a ``TextEditor`` draw it; an open menu's bar,
    /// beside options the menu is sized to, stays one cell, and a horizontal
    /// bar is a row, and stays one.
    ///
    /// ```swift
    /// List(files) { … }
    ///     .scrollbarWidth(2)
    /// ```
    ///
    /// - Parameter cells: `1` or `2`; anything else is the nearer of the two.
    /// - Returns: A view whose vertical scrollbars are that wide.
    public func scrollbarWidth(_ cells: Int) -> some View {
        environment(\.scrollbarWidth, min(2, max(1, cells)))
    }
}
