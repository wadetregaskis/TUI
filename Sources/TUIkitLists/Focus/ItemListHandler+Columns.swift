//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ItemListHandler+Columns.swift
//
//  A table's columns from the keyboard: Ctrl-K picks one, and while it is
//  picked the arrows choose another, `<`/`>` move it, `-`/`+` resize it and
//  Return opens the column menu on it — the keyboard's route to the gestures
//  a table's header takes from the pointer.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - What the keys reach

/// A table's column customization as the keyboard reaches it: built each frame
/// by a table with a header, from the columns it is showing — every one it may
/// resize, and with a ``TableColumnCustomization`` bound, every one it may
/// move, hide or open the menu on (decisions B-D4T-7). One that lists no
/// column is no customization at all: the keys go on to the rows.
///
/// Every member is asked when a key arrives, not when the table builds it, so
/// a table works out nothing for it on a frame no key reaches it.
package struct TableColumnEditing {
    /// The shown columns a user may customize, by identifier, in the order
    /// they are shown — as they stand now, asked of the customization: a key
    /// earlier in the same batch of input may have moved or hidden one since
    /// the frame was drawn.
    package var columns: [String] { currentColumns() }

    /// Lists ``columns``.
    package let currentColumns: () -> [String]

    /// Moves a column one place among the shown ones — `-1` left, `+1` right —
    /// when it and its neighbour may move.
    package let move: (_ id: String, _ delta: Int) -> Void

    /// Resizes a column by `delta` cells, within its bounds, when it may be
    /// resized.
    package let resize: (_ id: String, _ delta: Int) -> Void

    /// Opens the column menu on a column, under its header.
    package let openMenu: (_ id: String) -> Void

    /// Whether the column menu is open — the mode's own menu, which takes
    /// the focus without ending the mode.
    package let menuIsOpen: () -> Bool

    /// The memberwise initializer, written out: a synthesized one is internal,
    /// and a table in TUIkitTables makes these (module split, step C2).
    package init(
        currentColumns: @escaping () -> [String], move: @escaping (_ id: String, _ delta: Int) -> Void,
        resize: @escaping (_ id: String, _ delta: Int) -> Void, openMenu: @escaping (_ id: String) -> Void,
        menuIsOpen: @escaping () -> Bool
    ) {
        self.currentColumns = currentColumns
        self.move = move
        self.resize = resize
        self.openMenu = openMenu
        self.menuIsOpen = menuIsOpen
    }
}

// MARK: - The keys

extension ItemListHandler {
    /// The column keys: the chord that picks a column or lets it go, and while
    /// one is picked, the mode's own keys — a mode, like a row picked up with
    /// Ctrl-R, because a column has to be chosen before anything can be done
    /// to it, and the keys that do things to it need no modifier a terminal
    /// might not send.
    ///
    /// - Returns: `nil` for a key that is not a column key here, so it goes on
    ///   to the rows; `true` for one that was.
    func handleColumnKey(_ event: KeyEvent) -> Bool? {
        guard let editing = columnEditing, !editing.columns.isEmpty else {
            columnFocus = nil
            return nil
        }
        if shortcuts.action(for: event)?.action == .customizeColumns {
            columnFocus = columnFocus == nil ? editing.columns.first : nil
            return true
        }
        guard let focus = columnFocus else { return nil }
        // Escape lets the column go whatever has become of it: the mode owns
        // the key while it is on (the status bar says so), so it must never
        // fall through to the rows — which clear the selection on it, or with
        // none hand it to the page.
        if event.key == .escape {
            columnFocus = nil
            return true
        }
        // A column that has gone — hidden from its own menu, say — hands the
        // pick to the first one left (the table does the same when it draws,
        // so this is only met before a frame has). A mode key is spent on
        // that, not acted on for a column the user has not seen picked; any
        // other key goes on to the rows, as it would have anyway.
        guard let position = editing.columns.firstIndex(of: focus) else {
            guard Self.isColumnModeKey(event) else { return nil }
            columnFocus = editing.columns.first
            return true
        }
        switch event.key {
        case .left where !event.shift, .right where !event.shift:
            let step = event.key == .left ? -1 : 1
            columnFocus = editing.columns[max(0, min(editing.columns.count - 1, position + step))]
        case .left, .character("<"):
            editing.move(focus, -1)
        case .right, .character(">"):
            editing.move(focus, 1)
        case .character("-"), .character("_"):
            editing.resize(focus, -1)
        case .character("+"), .character("="):
            editing.resize(focus, 1)
        case .enter:
            editing.openMenu(focus)
        default:
            return nil
        }
        return true
    }

    /// Whether `event` is one of the keys the column mode acts on, besides
    /// Escape: the arrows that pick and move, `<`/`>`, `-`/`+` and their
    /// unshifted twins, and Return.
    private static func isColumnModeKey(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .left, .right, .enter,
            .character("<"), .character(">"), .character("-"), .character("_"),
            .character("+"), .character("="):
            return true
        default:
            return false
        }
    }
}
