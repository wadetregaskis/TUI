//  🖥️ TUI — A Terminal UI framework for Swift
//  RowSelectionEnvironment.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Row Selection Indicator Environment Key

/// Environment key for the selected row's `●` marker.
private struct RowSelectionIndicatorKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether a `List` or `Table` marks its selected row with a `●` in the
    /// gutter, in addition to the background highlight.
    ///
    /// - `.automatic` (default): a `List` draws the mark; a `Table` draws it
    ///   only where colour cannot show the selection — a terminal with no
    ///   colour at all — and gives its two cells back otherwise
    ///   (`RowSelectionIndicator.resolvingForTable(_:)`).
    /// - `.visible`: the mark is drawn, subject to
    ///   ``unfocusedSelectionVisibility``.
    /// - `.hidden`: it is not, and the highlight alone says which row is
    ///   selected. For a table of glyphs — where every row already begins with
    ///   a character the reader is there to look at — a second mark beside it
    ///   is one mark too many.
    ///
    /// A `Table` told `.hidden` gives the mark's two cells back rather than
    /// leaving them blank; the header indents by the same amount, so the
    /// titles stay over their columns either way. A `List` has nothing to give
    /// back — its mark goes in the one pad cell its rows already had.
    ///
    /// Set via ``View/rowSelectionIndicator(_:)``.
    package var rowSelectionIndicator: Visibility {
        get { self[RowSelectionIndicatorKey.self] }
        set { self[RowSelectionIndicatorKey.self] = newValue }
    }
}

// MARK: - Unfocused Selection Visibility Environment Key

/// Environment key for unfocused-selection-visibility configuration.
private struct UnfocusedSelectionVisibilityKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether a List or Table renders its selection highlight
    /// when the list itself does not have focus.
    ///
    /// - `.automatic` (default): resolves to visible — the
    ///   selected row is rendered with a desaturated accent
    ///   background while the list is unfocused, matching
    ///   desktop list-view convention (Finder, Explorer, etc.).
    /// - `.visible`: same as `.automatic` for now. Reserved for
    ///   future per-style behaviour.
    /// - `.hidden`: the selected row blends in with non-selected
    ///   rows while the list is unfocused. The selection binding
    ///   is unaffected; only the visual indicator is suppressed.
    ///   Useful when the list is a transient picker rather than a
    ///   persistent surface where the user expects to see what
    ///   they have selected at all times.
    ///
    /// Set via ``View/unfocusedSelectionVisibility(_:)``.
    package var unfocusedSelectionVisibility: Visibility {
        get { self[UnfocusedSelectionVisibilityKey.self] }
        set { self[UnfocusedSelectionVisibilityKey.self] = newValue }
    }
}
