//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShortcutsDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

/// SwiftUI's ⌘ shortcuts, written as SwiftUI writes them, in a terminal that
/// cannot send Command: `.commandKey(_:)` says which key stands in for it —
/// Control by default, Option, the bare key, or none — and every `⌘`
/// shortcut beneath it binds and prints as that key. TUI-specific: SwiftUI's
/// platforms never have to ask.
struct ShortcutsDemo: View {
    @State private var commandKey = CommandKeyBinding.control
    @State private var lastCommand = "—"

    var body: some View {
        DemoSection("page.menus.shortcuts") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.menus.shortcutsExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Picker("page.menus.shortcutsCommandKey", selection: $commandKey) {
                    Text("page.menus.shortcuts.control").tag(CommandKeyBinding.control)
                    Text("page.menus.shortcuts.option").tag(CommandKeyBinding.option)
                    Text("page.menus.shortcuts.bare").tag(CommandKeyBinding.bare)
                    Text("page.menus.shortcuts.unavailable").tag(CommandKeyBinding.unavailable)
                }
                HStack(spacing: 2) {
                    // Written exactly as in SwiftUI: `.keyboardShortcut("s")`
                    // is ⌘S. Each row prints the key it is bound to now.
                    Menu("page.menus.shortcutsFile") {
                        command("page.menus.shortcuts.new", "n")
                        command("page.menus.shortcuts.open", "o")
                        Divider()
                        command("page.menus.shortcuts.save", "s")
                        command("page.menus.shortcuts.saveAs", "s", modifiers: [.command, .shift])
                    }
                    // The read-out clears as the pop-up opens, so choosing
                    // `Save` twice shows two distinct choices (as the page's
                    // other pop-ups do).
                    .onMenuOpen { lastCommand = "—" }
                    ValueDisplayRow("page.menus.chose", lastCommand)
                }
            }
            .commandKey(commandKey)
        }
    }

    /// A menu item with a ⌘ shortcut, which records itself as chosen.
    private func command(
        _ key: String, _ character: Character, modifiers: EventModifiers = .command
    ) -> some View {
        Button(L(key)) { lastCommand = L(key) }
            .keyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}
