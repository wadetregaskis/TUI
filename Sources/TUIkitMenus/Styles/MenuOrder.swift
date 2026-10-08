//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuOrder.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Indicator and Order

/// The order in which a menu presents its items.
public struct MenuOrder: Equatable, Hashable, Sendable {
    private let rawValue: Int

    /// The ordering of the menu chosen by the system for the current context:
    /// here always top to bottom, as written — a terminal's menus open where
    /// they open and keep the order they were given.
    public static let automatic = Self(rawValue: 0)

    /// Keep the first items in the menu at the top: the order written.
    public static let fixed = Self(rawValue: 1)
}

private struct MenuOrderKey: EnvironmentKey {
    static let defaultValue = MenuOrder.automatic
}

private struct MenuIndicatorVisibilityKey: EnvironmentKey {
    static let defaultValue = Visibility.automatic
}

extension EnvironmentValues {
    /// The preferred order of items for menus presented from this view.
    ///
    /// Both orders draw the items as written: ``MenuOrder/automatic`` resolves
    /// to ``MenuOrder/fixed`` here, as it does on iOS for menus in scrolling
    /// content and on macOS always.
    public var menuOrder: MenuOrder {
        get { self[MenuOrderKey.self] }
        set { self[MenuOrderKey.self] = newValue }
    }

    /// Whether menus in this view show the caret beside their label.
    public var menuIndicatorVisibility: Visibility {
        get { self[MenuIndicatorVisibilityKey.self] }
        set { self[MenuIndicatorVisibilityKey.self] = newValue }
    }
}

extension View {
    /// Sets the preferred order of items for menus presented from this view.
    ///
    /// - Parameter order: The menu item ordering strategy to apply.
    /// - Returns: A view that uses `order` for the menus it presents.
    public func menuOrder(_ order: MenuOrder) -> some View {
        environment(\.menuOrder, order)
    }

    /// Sets the menu indicator visibility for controls within this view: the
    /// caret a ``Menu`` draws beside its label.
    ///
    /// - Parameter visibility: `.hidden` takes the caret away; `.visible` and
    ///   `.automatic` show it.
    /// - Returns: A view whose menus show or hide their caret.
    public func menuIndicator(_ visibility: Visibility) -> some View {
        environment(\.menuIndicatorVisibility, visibility)
    }
}
