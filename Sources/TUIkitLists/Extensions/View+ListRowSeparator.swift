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
    /// Where the terminal draws hairlines (Ghostty), a separator is a line a
    /// pixel or two thick along the top of the next row, which takes no row,
    /// and `.automatic` is SwiftUI's default: shown in every style but
    /// `.sidebar` and `.insetGrouped`. Elsewhere it is a faint `─` rule on a
    /// line of its own between this row and the next (decisions A47): drawn
    /// with cells, a separator costs a line of height, so `.automatic` is
    /// hidden and `.visible` asks for one. ``listSeparatorStyle(_:)`` chooses
    /// the look (decisions A-D6L-2). The line under a row is the row's
    /// `.bottom` edge; the line above a row is the row before it's, so `.top`
    /// is the style's to decline, as SwiftUI documents a style may. Never
    /// below a list's last row. Tint it
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
