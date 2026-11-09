//  🖥️ TUI — A Terminal UI framework for Swift
//  CommandsSessionHost.swift
//
//  The app a session's page is the whole of, with a menu bar: the commands an
//  ordinary app declares on its scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// ``SessionHost`` with commands on its scene, so the window draws a menu
/// bar: for a session that prices what a menu bar costs a frame
/// (``StressSession/declaresCommands``).
///
/// Every walk renders each closed menu's items for the keyboard shortcuts
/// they register (`_MenuBarCore`), which no scenario and no other session
/// draws: an app's scene is the one place commands live, and `--bench`
/// renders views, not scenes. The commands are an ordinary app's — the
/// standard editing and display ones, and a menu of its own whose items carry
/// shortcuts, with a toggle and a picker among them.
struct CommandsSessionHost<Page: View>: App {
    let page: Page?

    init(page: Page) { self.page = page }

    init() { page = nil }

    var body: some Scene {
        WindowGroup {
            if let page {
                page.toolbar {
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
            }
        }
        .commands { StressCommands() }
    }
}

/// The commands ``CommandsSessionHost`` declares. Their shortcuts are
/// Control chords no session's script sends, so the page's keys reach it as
/// they do under ``SessionHost``.
private struct StressCommands: Commands {
    var body: some Commands {
        TextEditingCommands()
        DisplayCommands()
        ToolbarCommands()
        SidebarCommands()
        CommandMenu(Text(verbatim: "Items")) {
            Button(String("Archive")) {}
                .keyboardShortcut("y", modifiers: .control)
            Button(String("Flag")) {}
                .keyboardShortcut("g", modifiers: .control)
            Button(String("Mark Unread")) {}
                .keyboardShortcut("u", modifiers: .control)
            Divider()
            Toggle(String("Show Previews"), isOn: .constant(true))
            Picker(String("Sort By"), selection: .constant(1)) {
                Text(verbatim: "Date").tag(0)
                Text(verbatim: "Sender").tag(1)
                Text(verbatim: "Subject").tag(2)
            }
            Divider()
            Button(String("Refresh")) {}
                .keyboardShortcut("r", modifiers: [.control, .shift])
        }
    }
}
