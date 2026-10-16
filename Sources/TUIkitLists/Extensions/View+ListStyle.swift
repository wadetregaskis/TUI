//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+ListStyle.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - List Style

extension View {
    /// Sets the list style for List views in this view and its descendants.
    ///
    /// The list style controls how lists render, including borders, padding,
    /// and row backgrounds. The built-in styles are SwiftUI's macOS ones —
    /// `.automatic`, `.bordered`, `.inset`, `.plain`, `.sidebar` — and iOS's
    /// `.insetGrouped`; see ``ListStyle``.
    ///
    /// # Example
    ///
    /// ```swift
    /// List {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///     }
    /// }
    /// .listStyle(.plain)
    ///
    /// List {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///     }
    /// }
    /// .listStyle(.insetGrouped)
    /// ```
    ///
    /// - Parameter style: The list style to apply.
    /// - Returns: A view with the list style applied.
    public func listStyle<S: ListStyle>(_ style: S) -> some View {
        environment(\.listStyle, style)
    }

    /// Controls whether a List or Table renders its selection
    /// highlight when the list itself does not have focus.
    ///
    /// Default — and the `.automatic` resolution — is to show the
    /// selected row with a desaturated accent background while
    /// the list is unfocused, matching desktop list-view
    /// convention. Use `.hidden` on transient surfaces (a pop-up
    /// picker, a quick-pick palette) where the unfocused
    /// highlight is more noise than signal.
    ///
    /// # Example
    ///
    /// ```swift
    /// List(items, selection: $selection) {
    ///     ForEach(items) { item in Text(item.name) }
    /// }
    /// .unfocusedSelectionVisibility(.hidden)
    /// ```
    ///
    /// The selection binding itself is unaffected; only the
    /// visual indicator is suppressed when the list lacks focus.
    /// A list that HOLDS the focus in a window that has lost the
    /// terminal's focus does not lack it: its cursor row stays,
    /// still, whatever this says (see "Focus system").
    /// Cascades through the environment so it can be set on a
    /// parent (e.g. a NavigationSplitView column) and inherited
    /// by every selection-bearing descendant.
    ///
    /// - Parameter visibility: The desired visibility.
    /// - Returns: A view with the unfocused-selection visibility
    ///   set on its environment.
    public func unfocusedSelectionVisibility(_ visibility: Visibility) -> some View {
        environment(\.unfocusedSelectionVisibility, visibility)
    }

    /// Whether a `List` or `Table` marks the selected row with a `●` beside
    /// it, or leaves the background highlight to say so on its own.
    ///
    /// # Example
    ///
    /// ```swift
    /// Table(glyphs, selection: $selection) { … }
    ///     .rowSelectionIndicator(.hidden)
    /// ```
    ///
    /// With the mark off, a focused control's cursor row still breathes, selected
    /// or not — the accent on a selected row, the neutral focus wash on one that is
    /// not — because the focus indicator always visibly breathes.
    ///
    /// TUI-specific: SwiftUI has no row marker to suppress. A `Table` told
    /// `.hidden` also gives back the two cells the mark would have occupied,
    /// so its columns start where any other bordered content does; a `List`
    /// draws its mark in the pad cell its rows already had and so has nothing
    /// to give back.
    ///
    /// Left `.automatic`, a `List` draws the mark, and a `Table` draws it only
    /// where colour cannot show the selection — a terminal with no colour —
    /// keeping its two cells for its columns everywhere else.
    ///
    /// - Parameter visibility: `.hidden` to leave the mark off; `.visible` to
    ///   draw it; `.automatic` (the default) as above.
    /// - Returns: A view with the row-selection-indicator visibility set on its
    ///   environment.
    public func rowSelectionIndicator(_ visibility: Visibility) -> some View {
        environment(\.rowSelectionIndicator, visibility)
    }
}
