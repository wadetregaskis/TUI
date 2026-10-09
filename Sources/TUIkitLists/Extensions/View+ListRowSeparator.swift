//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+ListRowSeparator.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - List Row Separator Modifier

extension View {
    /// Sets the display mode for the separator associated with this specific
    /// row.
    ///
    /// A separator is a faint `─` rule on a line of its own between this row and
    /// the next (decisions A47): a terminal row has no hairline thinner than a
    /// cell, so each separator costs a line of height. No built-in style draws
    /// them by default yet — `.automatic` is hidden — so `.visible` asks for
    /// one. The line under a row is the row's `.bottom` edge; the line above a
    /// row is the row before it's, so `.top` is the style's to decline, as
    /// SwiftUI documents a style may. Never below a list's last row. Tint it
    /// with ``listRowSeparatorTint(_:edges:)`` and place its ends with the
    /// ``HorizontalAlignment/listRowSeparatorLeading`` and
    /// ``HorizontalAlignment/listRowSeparatorTrailing`` guides.
    ///
    /// ```swift
    /// List {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///             .listRowSeparator(.visible)
    ///     }
    /// }
    /// ```
    ///
    /// Written on a `List` (or above one) rather than on a row, it is every
    /// row's in the lists below; a row's own still wins.
    ///
    /// - Parameters:
    ///   - visibility: The visibility of this row's separators.
    ///   - edges: The set of row edges for which this preference applies. The
    ///     default is ``VerticalEdge/Set/all``.
    /// - Returns: A row carrying the preference.
    public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        ListRowSeparatorModifier(content: self, visibility: visibility, edges: edges)
    }
}
