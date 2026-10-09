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
package final class SelectionContextMenu {
    /// The item type the modifier named, which must be the container's
    /// selection value type for the menu to be the container's.
    private(set) var itemType: Any.Type = Never.self

    /// Builds the menu for rows whose ids are these, or `nil` when one of them
    /// is not of ``itemType``.
    private var makeMenu: (([AnyHashable]) -> AnyView?)?

    /// The primary action, for rows whose ids are these.
    package var primaryAction: (([AnyHashable]) -> Void)? { _primaryAction }

    /// ``primaryAction``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _primaryAction: (([AnyHashable]) -> Void)?

    /// No arguments, spelled out because the implicit initializer is internal
    /// and TUIkitLists makes these, for its lists.
    package init() {}

    /// Takes the closures a body just built.
    package func refresh<Item: Hashable, Menu: View>(
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
        _primaryAction = primaryAction.map { action in
            { ids in action(Set(ids.compactMap { $0.base as? Item })) }
        }
    }

    /// Whether a container whose rows are identified by `ID` is the one this
    /// menu is for. SwiftUI asks that the type named match the container's
    /// selection type; one that does not never activates.
    package func isFor<ID>(_ type: ID.Type) -> Bool { itemType == ID.self }

    /// The menu for the rows `ids` — empty for a press on no row.
    package func menu(for ids: [AnyHashable]) -> AnyView? { makeMenu?(ids) }
}

/// What the environment carries: the menu by identity, and whether it has a
/// primary action — which changes what Return does, and what the status bar
/// says it does, so it is compared too.
///
/// `@usableFromInline`: the type of an `@inlinable` environment accessor (module split step A3).
///
/// `Sendable` stated, as it was inferred while the type was not usable from
/// inline code: the compiler infers it only for types that are not.
@usableFromInline
package struct SelectionContextMenuReference: Equatable, Sendable {
    package let menu: SelectionContextMenu
    package let hasPrimaryAction: Bool

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitLists makes these, for its lists.
    package init(menu: SelectionContextMenu, hasPrimaryAction: Bool) {
        self.menu = menu
        self.hasPrimaryAction = hasPrimaryAction
    }

    @usableFromInline
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.menu === rhs.menu && lhs.hasPrimaryAction == rhs.hasPrimaryAction
    }
}

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct SelectionContextMenuKey: EnvironmentKey {
    @usableFromInline static let defaultValue: SelectionContextMenuReference? = nil
}

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct RowsYieldSecondaryClickKey: EnvironmentKey {
    @usableFromInline static let defaultValue = false
}

extension EnvironmentValues {
    /// The selection menu a `List` or `Table` beneath this point takes as its
    /// own. The container clears it for its rows, so a list inside a row does
    /// not take its parent's.
    @inlinable
    package var selectionContextMenu: SelectionContextMenuReference? {
        get { self[SelectionContextMenuKey.self] }
        set { self[SelectionContextMenuKey.self] = newValue }
    }

    /// Whether the rows being drawn belong to a container whose selection menu
    /// answers every secondary click on them — set by that container for its
    /// rows, and read by `.contextMenu` on a view inside one, which then adds
    /// no menu of its own. Measured on macOS: with a selection menu on a list
    /// or table, a right-click on a row whose view has its own `.contextMenu`,
    /// or on a `TableRow` with one, shows the selection menu.
    @inlinable
    package var rowsYieldSecondaryClick: Bool {
        get { self[RowsYieldSecondaryClickKey.self] }
        set { self[RowsYieldSecondaryClickKey.self] = newValue }
    }
}
