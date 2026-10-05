//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TableRowContextMenu.swift
//
//  `TableRowContent.contextMenu(menuItems:)` and its `preview:` form: a menu
//  of a row's own, opened by a secondary click on the row or Shift+F10 on the
//  cursor row.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitView

// MARK: - The modifiers

/// What `TableRowContent.contextMenu(menuItems:)` records on a row: its menu.
public struct _ContextMenuTableRowModifier<M: View>: _TableRowContentModifier, _TableRowTraitModifier {
    let menuItems: M

    func apply(to traits: inout _TableRowTraits) {
        // The modifier nearest the row has already spoken.
        guard traits.contextMenu == nil else { return }
        let menuItems = menuItems
        traits.contextMenu = { AnyView(menuItems) }
    }
}

/// What `TableRowContent.contextMenu(menuItems:preview:)` records on a row:
/// its menu, and a preview that is not shown — as on macOS.
public struct _ContextMenuPreviewTableRowModifier<M: View, P: View>: _TableRowContentModifier,
    _TableRowTraitModifier
{
    let menuItems: M

    func apply(to traits: inout _TableRowTraits) {
        guard traits.contextMenu == nil else { return }
        let menuItems = menuItems
        traits.contextMenu = { AnyView(menuItems) }
    }
}

extension TableRowContent {
    /// Adds a context menu to a table row.
    ///
    /// ```swift
    /// Table(of: Person.self) {
    ///     TableColumn("Name", value: \.name)
    /// } rows: {
    ///     ForEach(people) { person in
    ///         TableRow(person)
    ///             .contextMenu {
    ///                 Button("Send Email…") { … }
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// A secondary click on the row opens it at the click — a right-click, or
    /// a Ctrl-click where the terminal keeps the right button for itself —
    /// and **Shift+F10** opens it on the cursor row while the table has the
    /// focus. Choosing an item runs it and closes the menu; Escape or a click
    /// elsewhere closes it. A row without a menu leaves a right-click to
    /// whatever is around the table.
    ///
    /// A `contextMenu(forSelectionType:menu:primaryAction:)` around the table
    /// answers every secondary click on its rows, this row's included — as on
    /// macOS, where the selection menu wins.
    ///
    /// - Parameter menuItems: The menu's contents. Return nothing for no menu.
    /// - Returns: A row that can display a context menu.
    public func contextMenu<M: View>(
        @ViewBuilder menuItems: () -> M
    ) -> ModifiedContent<Self, _ContextMenuTableRowModifier<M>> {
        ModifiedContent(content: self, modifier: _ContextMenuTableRowModifier(menuItems: menuItems()))
    }

    /// Adds a context menu with a preview to a table row.
    ///
    /// The menu is the one ``TableRowContent/contextMenu(menuItems:)`` shows,
    /// opened the same ways. The preview is not shown, as on macOS: SwiftUI
    /// documents that this modifier "produces a context menu on macOS, but that
    /// platform doesn't display the preview". The `preview` closure is never
    /// called.
    ///
    /// - Parameters:
    ///   - menuItems: The menu's contents. Return nothing for no menu.
    ///   - preview: The view iOS shows beside the menu; not shown here.
    /// - Returns: A row that can display a context menu.
    public func contextMenu<M: View, P: View>(
        @ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P
    ) -> ModifiedContent<Self, _ContextMenuPreviewTableRowModifier<M, P>> {
        ModifiedContent(
            content: self, modifier: _ContextMenuPreviewTableRowModifier(menuItems: menuItems()))
    }
}
