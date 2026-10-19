//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowsHugEnvironment.swift
//
//  Whether the list a row is drawn in hugs its rows, for a row that would put
//  something at the list's trailing edge.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

/// Environment key for ``EnvironmentValues/listRowsHug``.
private struct ListRowsHugKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the `List` drawing these rows hugs them — under
    /// `.fixedSize(horizontal:)`, as a tab view's sidebar does — rather than
    /// filling the width it is offered.
    ///
    /// A list that hugs settles its width from its rows', after they are
    /// drawn, so a row cannot place anything at that width's trailing edge:
    /// a section's actions (``View/sectionActions(content:)``) go one cell
    /// after its title there, and flush right in a list that fills, whose
    /// width the rows are drawn at.
    ///
    /// Written by the list, straight into its rows' environment where it
    /// changes, as it writes the rest of what it tells them: a list hugs or
    /// fills by its place in the layout, not from one frame to the next.
    var listRowsHug: Bool {
        get { self[ListRowsHugKey.self] }
        set { self[ListRowsHugKey.self] = newValue }
    }
}
