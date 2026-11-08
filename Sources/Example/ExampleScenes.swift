//  🖥️ TUI — A Terminal UI framework for Swift
//  ExampleScenes.swift
//
//  The Example's scenes beside its main window: an Inspector window, opened
//  over it with `openWindow(id:)`, and the Settings scene, the settings
//  panel's first tab.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - The Inspector

/// The Inspector window's content: a `Window` scene's, opened over the main
/// window with `openWindow(id: "inspector")` — from the Menus page, or the menu
/// bar's Window menu — and closed with Escape, its Close button
/// (`dismissWindow()`) or Window ▸ Close Window.
///
/// Its count is `@SceneStorage`, which is per window: kept under the
/// Inspector's own namespace, apart from anything the main window stores
/// under the same key.
struct ExampleInspector: View {
    @SceneStorage("example.inspector.count") private var count = 0
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("inspector.title").bold()
            Text("inspector.explain")
                .foregroundStyle(.palette.foregroundSecondary)
            HStack(spacing: 2) {
                Button("inspector.count") { count += 1 }
                Text("\(count)")
            }
            HStack(spacing: 2) {
                SettingsLink()
                Button("inspector.close") { dismissWindow() }
            }
        }
        .padding()
        .frame(maxWidth: 72)
        // The line of key hints, as the main window has: it names Escape's
        // "close window" while another window is open behind this one.
        .toolbar {
            ToolbarItem(placement: .bottomBar) { StatusBar() }
        }
    }
}

// MARK: - The Settings

/// The Settings scene's content, the first tab of the settings panel, which
/// F2, the app menu's Settings…, ⌃, or a `SettingsLink` presents over the
/// window in front, before TUI's View and Accessibility tabs: two of the
/// app-wide styling switches the Theme page has, bound to the app's state, so
/// a change shows on every page at once.
struct ExampleSettings: View {
    @Binding var styling: ExampleStyling

    var body: some View {
        Form {
            Section("settings.title") {
                Text("settings.explain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Toggle("settings.uppercaseHeaders", isOn: $styling.uppercaseSectionHeaders)
                Toggle("settings.boldButtons", isOn: $styling.boldButtons)
            }
        }
    }
}
