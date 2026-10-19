//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StandardCommands.swift
//
//  SwiftUI's built-in command sets an app opts into: the sidebar's, the
//  toolbar's, the inspector's, and text editing's.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Sidebar Commands

/// A built-in set of commands for manipulating window sidebars — mirrors
/// SwiftUI's `SidebarCommands`.
///
/// These commands are optional and can be explicitly requested by passing a
/// value of this type to the `Scene.commands(content:)` modifier. They add View ▸
/// Show Sidebar (Hide Sidebar while it shows), as on macOS, on the window's
/// first `NavigationSplitView`'s sidebar: the same as the split view's own
/// ⌃⌘S (⌃S under the default `commandKey`), which choosing it presses, so it
/// toggles the split view that holds the focus first. Disabled where no split
/// view is on the screen.
public struct SidebarCommands: Commands {
    @Environment(\.windowChrome) private var chrome
    @Environment(\.keysAfterFrame) private var keys
    @Environment(\.commandKey) private var commandKey

    /// Creates the sidebar commands.
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            let toggle = chrome?.panelToggle(.sidebar)
            let chord = KeyboardShortcut("s", modifiers: [.command, .control])
            let press = chord.keyEvent(commandKey: commandKey)
            Button(PanelLabels.title(showing: toggle?.isShown ?? false, show: .showSidebar, hide: .hideSidebar)) {
                press.map { keys?.press($0) }
            }
            .keyboardShortcutHint(chord)
            .disabled(toggle == nil || press == nil)
        }
    }
}

// MARK: - Inspector Commands

/// A built-in set of commands for manipulating inspectors — mirrors SwiftUI's
/// `InspectorCommands`.
///
/// These commands are optional and can be explicitly requested by passing a
/// value of this type to the `Scene.commands(content:)` modifier. They add View ▸
/// Show Inspector (Hide Inspector while it shows), on ⌃⌘I as on macOS, for the
/// window's first `inspector(isPresented:content:)`; disabled where there is
/// none, as there. Under the default `commandKey`, ⌃⌘I is ⌃I, which a terminal
/// sends as Tab unless it speaks the kitty keyboard protocol, so the menu is
/// the way to it on most hosts.
public struct InspectorCommands: Commands {
    @Environment(\.windowChrome) private var chrome

    /// Creates the inspector commands.
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            let toggle = chrome?.panelToggle(.inspector)
            Button(PanelLabels.title(showing: toggle?.isShown ?? false, show: .showInspector, hide: .hideInspector)) {
                toggle?.action.perform()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(toggle == nil)
        }
    }
}

// MARK: - Toolbar Commands

/// A built-in set of commands for manipulating window toolbars — mirrors
/// SwiftUI's `ToolbarCommands`.
///
/// These commands are optional and can be explicitly requested by passing a
/// value of this type to the `Scene.commands(content:)` modifier. They add View ▸
/// Hide Toolbar (Show Toolbar while it is hidden), on ⌥⌘T as on macOS: the
/// window's top bar goes, whatever the page declares, until Show Toolbar
/// brings it back. Disabled while the page places nothing in the top bar. And
/// View ▸ Customize Toolbar…, which opens the customization panel of the
/// page's customizable toolbar (`toolbar(id:content:)`); disabled while it has
/// none.
public struct ToolbarCommands: Commands {
    @Environment(\.windowChrome) private var chrome

    /// Creates the toolbar commands.
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            let hidden = chrome?.topBarHiddenByCommand ?? false
            let declared = !(chrome?.declaredEntries(for: .top).isEmpty ?? true)
            Button(PanelLabels.title(showing: !hidden, show: .showToolbar, hide: .hideToolbar)) {
                chrome?.topBarHiddenByCommand.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(!hidden && !declared)
            Button(LocalizationService.shared.string(for: LocalizationKey.Label.customizeToolbar)) {
                chrome?.beginCustomizingToolbar()
            }
            .disabled(chrome?.customizableToolbars.isEmpty ?? true)
        }
    }
}

// MARK: - Text Editing Commands

/// A built-in group of commands for searching, editing, and transforming
/// selections of text — mirrors SwiftUI's `TextEditingCommands`.
///
/// These commands are optional and can be explicitly requested by passing a
/// value of this type to the `Scene.commands(content:)` modifier. They add Edit ▸
/// Find…, which presses a `TextEditor`'s own find key, ⌃G (⌃F moves its caret
/// forward), once the menu has closed: the focused editor shows its find bar.
/// macOS's other text-editing submenus (spelling, substitutions,
/// transformations, speech) have no counterpart in a terminal's text controls.
public struct TextEditingCommands: Commands {
    @Environment(\.keysAfterFrame) private var keys

    /// Creates the text editing commands.
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .textEditing) {
            let find = KeyboardShortcut("g", modifiers: .control)
            Button(LocalizationService.shared.string(for: LocalizationKey.Menu.find)) {
                find.keyEvent(commandKey: .control).map { keys?.press($0) }
            }
            .keyboardShortcutHint(find)
        }
    }
}

// MARK: - Titles

/// The titles of the items that show or hide a panel.
private enum PanelLabels {
    /// `hide`'s title while the panel shows, `show`'s while it does not.
    static func title(showing: Bool, show: LocalizationKey.Label, hide: LocalizationKey.Label) -> String {
        LocalizationService.shared.string(for: showing ? hide : show)
    }
}
