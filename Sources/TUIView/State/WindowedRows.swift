//  🖥️ TUI — A Terminal UI framework for Swift
//  WindowedRows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Which rows a container that windows them — a lazy stack, a `List`, a
/// `Table` — drew in one walk, kept for a question asked after it: whether a
/// view that drew nothing was LEFT OUT of the window, its row still among the
/// container's rows and not drawn (``StateStorage/wasLeftOutOfAWindow(_:)``).
///
/// Not the same as being below a container that windows. A view can draw
/// nothing below a drawn `List` because the branch it was in was not taken, a
/// `DisclosureGroup` around it was collapsed, or its row left the data — and
/// none of those is the window's doing. Only the container knows which of its
/// rows a view lies in and whether it drew that row, so it says so, by two
/// questions answered only when asked: the record holds what the walk had in
/// hand, not an answer for every row.
package struct WindowedRows {
    /// The container's own identity: no view outside it lies in its rows.
    let root: ViewIdentity
    /// The row of the container's that `identity` (below ``root``) lies in,
    /// by ordinal — or `nil` when it lies in none of them.
    let row: @MainActor (_ identity: ViewIdentity) -> Int?
    /// Whether the walk drew the row at an ordinal.
    let isDrawn: @MainActor (_ ordinal: Int) -> Bool

    /// - Parameters:
    ///   - root: The windowing container's own identity.
    ///   - row: The row a view below `root` lies in, or `nil` for none — a
    ///     branch the content no longer takes, a row no longer in the data.
    ///   - isDrawn: Whether the walk drew a row.
    package init(
        root: ViewIdentity,
        row: @escaping @MainActor (_ identity: ViewIdentity) -> Int?,
        isDrawn: @escaping @MainActor (_ ordinal: Int) -> Bool
    ) {
        self.root = root
        self.row = row
        self.isDrawn = isDrawn
    }

    /// A container whose rows' identities can be asked by ordinal, which
    /// finds a view's row by looking through them for the one at or above it.
    ///
    /// - Parameters:
    ///   - root: The windowing container's own identity.
    ///   - count: How many rows it has.
    ///   - identity: Each row's identity, or `nil` for a row that has none
    ///     (drawn whatever the window, so never left out of it).
    ///   - isDrawn: Whether the walk drew a row.
    package init(
        root: ViewIdentity, count: Int,
        identity: @escaping @MainActor (_ ordinal: Int) -> ViewIdentity?,
        isDrawn: @escaping @MainActor (_ ordinal: Int) -> Bool
    ) {
        self.init(
            root: root,
            row: { view in
                (0..<count).first { ordinal in
                    guard let row = identity(ordinal) else { return false }
                    return row == view || row.isAncestor(of: view)
                }
            },
            isDrawn: isDrawn)
    }

    /// Whether `identity` lies in one of these rows that the walk did not draw.
    @MainActor
    func leftOut(_ identity: ViewIdentity) -> Bool {
        guard root.isAncestor(of: identity), let ordinal = row(identity) else { return false }
        return !isDrawn(ordinal)
    }
}
