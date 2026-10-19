//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomizableToolbarDeclaration.swift
//
//  A customizable toolbar (`toolbar(id:content:)`) as a walk declared it: what
//  the customization panel lists, and what the menu bar's Customize Toolbar…
//  opens.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A Declared Customizable Toolbar

/// A customizable toolbar a walk declared (`toolbar(id:content:)`,
/// TUIkitChrome): its identifier, each of its customizable items — the ones
/// in the bar and the ones the person or the app took out of it — and how to
/// change what the person chose.
///
/// Walk-scoped, in ``WindowChromeState``: the toolbar's module records it
/// there, so the bar's customization panel and the menu bar's View ▸ Customize
/// Toolbar… (TUIkitCommands) can find it.
package struct CustomizableToolbarDeclaration {
    /// One customizable item: a `ToolbarItem(id:)` in the toolbar.
    package struct Item {
        /// Its identifier, unique in the toolbar.
        package let id: String
        /// What it draws, to show in the panel.
        package let view: AnyView
        /// Whether the person may take it out of the bar (`.default`).
        package let isRemovable: Bool
        /// Whether the person may move it one place earlier: it is movable
        /// (`.default`, `.reorderable`), and so is an item before it in its
        /// place in the bar.
        package let canMoveEarlier: Bool
        /// Whether the person may move it one place later, as
        /// ``canMoveEarlier``.
        package let canMoveLater: Bool
        /// Whether it is in the bar now — the person's choice, else its
        /// default (`defaultCustomization(_:options:)`).
        package let isShown: Bool
        /// Whether the app hid it (`CustomizableToolbarContent.hidden(_:)`):
        /// out of the bar whatever the person chose, and listed in the panel.
        package let isHiddenByApp: Bool

        package init(
            id: String, view: AnyView, isRemovable: Bool, canMoveEarlier: Bool, canMoveLater: Bool, isShown: Bool,
            isHiddenByApp: Bool
        ) {
            self.id = id
            self.view = view
            self.isRemovable = isRemovable
            self.canMoveEarlier = canMoveEarlier
            self.canMoveLater = canMoveLater
            self.isShown = isShown
            self.isHiddenByApp = isHiddenByApp
        }
    }

    /// The toolbar's identifier.
    package let id: String

    /// Its customizable items, in the order the bars draw them.
    package let items: [Item]

    /// The environment of the view that declared it, for the panel to draw
    /// the items in.
    package let environment: EnvironmentValues

    /// Puts the item with `id` in the bar or takes it out.
    package let setShown: @MainActor (_ id: String, _ isShown: Bool) -> Void

    /// Moves the item with `id` past the movable item before it in its place
    /// in the bar (`offset` −1) or after it (`offset` 1): an item moved past
    /// one in another place would stay where it was in the bar.
    package let move: @MainActor (_ id: String, _ offset: Int) -> Void

    /// Forgets everything the person chose: the items as the app declared
    /// them.
    package let reset: @MainActor () -> Void

    package init(
        id: String, items: [Item], environment: EnvironmentValues,
        setShown: @escaping @MainActor (String, Bool) -> Void, move: @escaping @MainActor (String, Int) -> Void,
        reset: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.items = items
        self.environment = environment
        self.setShown = setShown
        self.move = move
        self.reset = reset
    }
}
