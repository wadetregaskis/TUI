//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+StatusBarItems.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitFoundation

// MARK: - Status Bar Items

extension View {
    /// Sets the status bar items for this view.
    ///
    /// When this view is rendered, the specified items will be displayed
    /// in the status bar. This replaces any existing global items.
    ///
    /// If a user item uses the same shortcut string as a system item
    /// (for example `q`), the user item wins in both display and event
    /// handling for that view context.
    ///
    /// # Example
    ///
    /// ```swift
    /// struct MainView: View {
    ///     var body: some View {
    ///         VStack {
    ///             Text("Main Content")
    ///         }
    ///         .statusBarItems([
    ///             StatusBarItem(shortcut: "q", label: "quit"),
    ///             StatusBarItem(shortcut: "h", label: "help") { showHelp() }
    ///         ])
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter items: The status bar items to display.
    /// - Returns: A view that sets the specified status bar items.
    public func statusBarItems(_ items: [any StatusBarItemProtocol]) -> some View {
        StatusBarItemsModifier(content: self, items: items, composition: .merge, context: nil)
    }

    /// Declares status bar items for this view using a builder.
    ///
    /// When used inside a `.focusSection()`, items are composed with parent
    /// items using the `.merge` strategy (default). Use
    /// ``statusBarItems(_:_:)`` to specify a different strategy.
    ///
    /// A user-defined item can intentionally override a system shortcut such
    /// as `q`. When the item has an action, it intercepts the key before the
    /// built-in quit binding runs.
    ///
    /// # Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("Main Content")
    /// }
    /// .statusBarItems {
    ///     StatusBarItem(shortcut: "q", label: "quit")
    ///     StatusBarItem(shortcut: "h", label: "help") { showHelp() }
    /// }
    /// ```
    ///
    /// - Parameter builder: A closure that returns the status bar items.
    /// - Returns: A view that declares the specified status bar items.
    public func statusBarItems(
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: builder(), composition: .merge, context: nil)
    }

    /// Declares status bar items with a specific composition strategy.
    ///
    /// - **`.merge`** (default): Items are combined with parent items.
    ///   Child wins on shortcut conflict.
    /// - **`.replace`**: Items replace all parent items (cascade barrier).
    ///
    /// Shortcut conflicts are resolved in favor of the most local user item.
    /// This also applies to system shortcuts such as `q`.
    ///
    /// # Example
    ///
    /// ```swift
    /// // Modal: replace all parent items
    /// SettingsView()
    ///     .focusSection("settings")
    ///     .statusBarItems(.replace) {
    ///         StatusBarItem(shortcut: Shortcut.escape, label: "close")
    ///         StatusBarItem(shortcut: Shortcut.enter, label: "confirm")
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - composition: How to compose with parent items.
    ///   - builder: A closure that returns the status bar items.
    /// - Returns: A view that declares the specified status bar items.
    public func statusBarItems(
        _ composition: StatusBarItemComposition,
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: builder(), composition: composition, context: nil)
    }

    /// Sets the status bar items for this view with a named context.
    ///
    /// This is the legacy push/pop API. Prefer using `.statusBarItems { ... }`
    /// with `.focusSection()` for declarative composition.
    ///
    /// - Parameters:
    ///   - context: A unique identifier for this context.
    ///   - builder: A closure that returns the status bar items.
    /// - Returns: A view that pushes status bar items to the context stack.
    public func statusBarItems(
        context: String,
        @StatusBarItemBuilder _ builder: () -> [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: builder(), composition: .merge, context: context)
    }

    /// Sets the status bar items for this view with a named context.
    ///
    /// This is the legacy push/pop API. Prefer using `.statusBarItems()` with
    /// `.focusSection()` for declarative composition.
    ///
    /// - Parameters:
    ///   - context: A unique identifier for this context.
    ///   - items: The status bar items to display.
    /// - Returns: A view that pushes status bar items to the context stack.
    public func statusBarItems(
        context: String,
        items: [any StatusBarItemProtocol]
    ) -> some View {
        StatusBarItemsModifier(content: self, items: items, composition: .merge, context: context)
    }
}
