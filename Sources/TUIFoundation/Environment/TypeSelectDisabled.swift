//  🖥️ TUI — A Terminal UI framework for Swift
//  TypeSelectDisabled.swift
//
//  Whether the lists, tables, picker drop-downs and pop-up menus in a subtree
//  find their rows by typed characters (type select). On by default; the
//  owner's APPFB-3, 2026-11-14, gave apps the switch to turn it off.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Environment key

/// `\.isTypeSelectEnabled`'s key.
private struct TypeSelectEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the lists, tables, `Picker` drop-downs and pop-up menus in this
    /// subtree move to a row when the user types its first characters — see
    /// ``View/typeSelectDisabled(_:)``. `true` by default.
    ///
    /// Named as SwiftUI names the value behind `.scrollDisabled(_:)`
    /// (`isScrollEnabled`). TUI-specific: SwiftUI has no switch for it.
    public var isTypeSelectEnabled: Bool {
        get { self[TypeSelectEnabledKey.self] }
        set { self[TypeSelectEnabledKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Turns type select off, or back on, for the lists, tables, `Picker`
    /// drop-downs and pop-up menus in this subtree.
    ///
    /// With a list or table focused, or a drop-down or menu open, typing a
    /// row's first characters moves to it (type select), and every printable
    /// character but Space is type select's, whether or not a row answers to
    /// it: no bare-key shortcut or status-bar item hears one meanwhile. That
    /// keeps TUI's shortcuts on modifier keys, as macOS keeps them on ⌘. Where
    /// an app would rather give the letters to its own bare keys while one of
    /// these has the focus, set this:
    ///
    /// ```swift
    /// Table(processes, selection: $selection) {
    ///     TableColumn("Name", value: \.name)
    /// }
    /// .typeSelectDisabled()
    /// .statusBarItems {
    ///     StatusBarItem(shortcut: "k", label: "kill") { kill(selection) }
    /// }
    /// ```
    ///
    /// A typed character then moves nothing, and goes on as though the
    /// control were not there: to a `.keyboardShortcut` with no modifiers, a
    /// status-bar item's action, a row's bare key equivalent in an open menu,
    /// or TUI's own keys, and the status bar shows the items on those keys
    /// again. An `onKeyPress` on the control, or around it, hears its key
    /// ahead of type select either way, so it needs none of this. The arrows,
    /// Space, Return and every other key work as before.
    ///
    /// Like ``View/scrollDisabled(_:)`` the nearest setting wins, so
    /// `.typeSelectDisabled(false)` turns it back on for one control inside a
    /// subtree that has it off.
    ///
    /// TUI-specific: SwiftUI's type select cannot be turned off.
    ///
    /// - Parameter disabled: Whether to turn type select off.
    /// - Returns: A view whose lists, tables, drop-downs and menus find no row
    ///   by typed characters, or do again.
    nonisolated public func typeSelectDisabled(_ disabled: Bool = true) -> some View {
        environment(\.isTypeSelectEnabled, !disabled)
    }
}
