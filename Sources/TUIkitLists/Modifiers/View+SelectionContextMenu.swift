//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+SelectionContextMenu.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - The modifier

/// The view `contextMenu(forSelectionType:menu:primaryAction:)` returns: its
/// content, with the menu in the environment for the list or table inside.
struct _SelectionContextMenuModifier<Content: View, Item: Hashable, Menu: View>: View {
    let content: Content
    let menu: (Set<Item>) -> Menu
    let primaryAction: ((Set<Item>) -> Void)?

    /// The menu the container reads, kept across bodies so it keeps one
    /// identity. A class held in `@State`, refreshed in place: the same shape
    /// `.searchable` gives `\.dismissSearch`.
    @State private var reference = SelectionContextMenu()

    var body: some View {
        reference.refresh(menu: menu, primaryAction: primaryAction)
        return content.environment(
            \.selectionContextMenu,
            SelectionContextMenuReference(menu: reference, hasPrimaryAction: primaryAction != nil))
    }
}

extension View {
    /// Adds an item-based context menu to a view: one menu for the rows of the
    /// `List` or ``Table`` it wraps, built from the rows it acts on.
    ///
    /// ```swift
    /// List(items, selection: $selection) { Text($0.name) }
    ///     .contextMenu(forSelectionType: Item.ID.self) { ids in
    ///         if ids.isEmpty {
    ///             Button("New Item") { … }
    ///         } else {
    ///             Button("Delete \(ids.count)", role: .destructive) { … }
    ///         }
    ///     } primaryAction: { ids in
    ///         open(ids)
    ///     }
    /// ```
    ///
    /// The set the closures receive, as measured on macOS:
    ///
    /// - a secondary click on a **selected** row: the whole selection;
    /// - on a row that is **not** selected: that row alone, the selection
    ///   untouched;
    /// - on the container's **empty** space: no rows, whatever is selected.
    ///   A table's column header is not its empty space: a right-click there
    ///   goes on to a menu around the table, as on macOS.
    ///
    /// A secondary click is a right-click, or a Ctrl-click where the terminal
    /// takes the right button for itself (iTerm2 does by default) — on a list
    /// or table with a menu, Ctrl-click is the menu's, as on macOS; Option-click
    /// still toggles a row's selection. From the keyboard, **Shift+F10** (or
    /// the Menu key, where the terminal reports it) opens the menu on the
    /// cursor row by the same rule. A menu that builds nothing
    /// for a set does not open, and the click that asked for it is spent all
    /// the same — its release selects nothing.
    ///
    /// While the container has this menu, it answers every secondary click on
    /// its rows: a `.contextMenu` on a row's view, or a `TableRow`'s own,
    /// does not open — as on macOS, where the selection menu wins.
    ///
    /// `primaryAction` runs on a double-click on a row and on Return with the
    /// container focused, with the set the same rule gives for that row — the
    /// row double-clicked (its first click having selected it), or the cursor
    /// row. With a primary action, Return activates and Space still selects.
    /// A container whose rows are not identified by `I`, and a `List` with no
    /// selection binding (measured on macOS), take neither the menu nor the
    /// action, and leave their rows' own menus be.
    ///
    /// - Parameters:
    ///   - itemType: The identifier type of the rows; it must match the
    ///     container's selection type.
    ///   - menu: Builds the menu for the set of rows it acts on — empty for
    ///     a click on no row. Return nothing to show no menu.
    ///   - primaryAction: Performed on the rows a double-click or Return
    ///     acts on.
    /// - Returns: A view whose list or table shows the menu.
    public func contextMenu<I: Hashable, M: View>(
        forSelectionType itemType: I.Type = I.self,
        @ViewBuilder menu: @escaping (Set<I>) -> M,
        primaryAction: ((Set<I>) -> Void)? = nil
    ) -> some View {
        _SelectionContextMenuModifier(content: self, menu: menu, primaryAction: primaryAction)
    }
}
