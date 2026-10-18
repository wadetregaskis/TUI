//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CommandMenu.swift
//
//  A menu of the app's own in the menu bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Command Menu

/// Command menus are stand-alone, top-level containers for controls that
/// perform related, app-specific commands — mirrors SwiftUI's `CommandMenu`.
///
/// Command menus are drawn as menus of the menu bar, inserted between the
/// standard View and Window menus in order of declaration, as SwiftUI inserts
/// them on macOS (measured on macOS 15.8: the session notes'
/// `O13/probe/menus.swift`). A menu is drawn even when it holds nothing, and two
/// with the same name are two menus, as there.
///
/// The menu's items are what a ``Menu``'s are — `Button`s, `Toggle`s,
/// `Divider`s and `Section`s — with their shortcuts, which work whether the menu
/// is open or not:
///
/// ```swift
/// CommandMenu("Note") {
///     Button("Duplicate") { duplicate() }
///         .keyboardShortcut("d")
///     Divider()
///     Button("Delete", role: .destructive) { delete() }
/// }
/// ```
public struct CommandMenu<Content: View>: Commands {
    /// The menu's name, as the menu bar shows it.
    let name: Text

    /// The menu's items.
    let content: Content

    /// Creates a new menu with a localized name for a collection of app-specific
    /// commands, inserted in the standard location for app menus (after the
    /// View menu, in order with other command menus).
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - nameKey: A localized string key for the command menu's label.
    ///   - content: The menu content.
    public init(_ nameKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.name = Text(nameKey)
        self.content = content()
    }

    /// Creates a new menu for a collection of app-specific commands, inserted
    /// in the standard location for app menus (after the View menu, in order
    /// with other command menus).
    ///
    /// - Parameters:
    ///   - name: A text view to use as the menu's label.
    ///   - content: The menu content.
    public init(_ name: Text, @ViewBuilder content: () -> Content) {
        self.name = name
        self.content = content()
    }

    /// Creates a new menu for a collection of app-specific commands, named as
    /// written, inserted in the standard location for app menus (after the
    /// View menu, in order with other command menus).
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - name: A string to use as the menu's label.
    ///   - content: The menu content.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ name: S, @ViewBuilder content: () -> Content) {
        self.name = Text(String(name))
        self.content = content()
    }

    /// Never called: a command menu hands itself over to the menu bar.
    public var body: Never { fatalError("CommandMenu hands its commands over itself") }
}

extension CommandMenu: _CommandsPrimitive {
    func collectCommands(into collector: inout CommandsCollector) {
        collector.addMenu(named: name, items: collector.items(content))
    }
}
