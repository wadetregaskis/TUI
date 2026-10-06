//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SelectionContextMenu.swift
//
//  `contextMenu(forSelectionType:menu:primaryAction:)`: one menu for the rows
//  of the `List` or `Table` beneath it, built from the set of rows it acts on,
//  and the action a double-click or Return performs on that set.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - What the container reads

/// A `.contextMenu(forSelectionType:menu:primaryAction:)` as the list or table
/// beneath it reads it: the menu for a set of rows and the primary action,
/// with the item type erased.
///
/// Kept by the modifier as `@State` and refreshed from each body, so the
/// container always reaches the closures the app's latest body built — and
/// handed down by identity (``SelectionContextMenuReference``) rather than as
/// the closures themselves, which cannot be compared and would turn every
/// memo beneath the modifier off. The container reads the closures only when
/// a menu opens or a row is activated, never while drawing, so an identity
/// that does not change says everything a memo needs to know.
@MainActor
final class SelectionContextMenu {
    /// The item type the modifier named, which must be the container's
    /// selection value type for the menu to be the container's.
    private(set) var itemType: Any.Type = Never.self

    /// Builds the menu for rows whose ids are these, or `nil` when one of them
    /// is not of ``itemType``.
    private var makeMenu: (([AnyHashable]) -> AnyView?)?

    /// The primary action, for rows whose ids are these.
    private(set) var primaryAction: (([AnyHashable]) -> Void)?

    /// Takes the closures a body just built.
    func refresh<Item: Hashable, Menu: View>(
        menu: @escaping (Set<Item>) -> Menu, primaryAction: ((Set<Item>) -> Void)?
    ) {
        itemType = Item.self
        makeMenu = { ids in
            var items = Set<Item>()
            for id in ids {
                guard let item = id.base as? Item else { return nil }
                items.insert(item)
            }
            return AnyView(menu(items))
        }
        self.primaryAction = primaryAction.map { action in
            { ids in action(Set(ids.compactMap { $0.base as? Item })) }
        }
    }

    /// Whether a container whose rows are identified by `ID` is the one this
    /// menu is for. SwiftUI asks that the type named match the container's
    /// selection type; one that does not never activates.
    func isFor<ID>(_ type: ID.Type) -> Bool { itemType == ID.self }

    /// The menu for the rows `ids` — empty for a press on no row.
    func menu(for ids: [AnyHashable]) -> AnyView? { makeMenu?(ids) }
}

/// What the environment carries: the menu by identity, and whether it has a
/// primary action — which changes what Return does, and what the status bar
/// says it does, so it is compared too.
struct SelectionContextMenuReference: Equatable {
    let menu: SelectionContextMenu
    let hasPrimaryAction: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.menu === rhs.menu && lhs.hasPrimaryAction == rhs.hasPrimaryAction
    }
}

private struct SelectionContextMenuKey: EnvironmentKey {
    static let defaultValue: SelectionContextMenuReference? = nil
}

private struct RowsYieldSecondaryClickKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The selection menu a `List` or `Table` beneath this point takes as its
    /// own. The container clears it for its rows, so a list inside a row does
    /// not take its parent's.
    var selectionContextMenu: SelectionContextMenuReference? {
        get { self[SelectionContextMenuKey.self] }
        set { self[SelectionContextMenuKey.self] = newValue }
    }

    /// Whether the rows being drawn belong to a container whose selection menu
    /// answers every secondary click on them — set by that container for its
    /// rows, and read by `.contextMenu` on a view inside one, which then adds
    /// no menu of its own. Measured on macOS: with a selection menu on a list
    /// or table, a right-click on a row whose view has its own `.contextMenu`,
    /// or on a `TableRow` with one, shows the selection menu.
    var rowsYieldSecondaryClick: Bool {
        get { self[RowsYieldSecondaryClickKey.self] }
        set { self[RowsYieldSecondaryClickKey.self] = newValue }
    }
}

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
    /// still toggles a row's selection. From the keyboard, **Shift+F10** opens
    /// the menu on the cursor row by the same rule. A menu that builds nothing
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
