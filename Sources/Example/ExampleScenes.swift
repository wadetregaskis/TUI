//  🖥️ TUI — A Terminal UI framework for Swift
//  ExampleScenes.swift
//
//  The Example's scenes beside its main window: an Inspector window, opened
//  over it with `openWindow(id:)`, and the Settings scene, presented as a
//  sheet.
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

/// The Settings scene's content, presented as a sheet over the window in
/// front by the app menu's Settings…, ⌃, or a `SettingsLink`: two of the
/// app-wide styling switches the Theme page has, bound to the app's state, so
/// a change shows on every page at once.
struct ExampleSettings: View {
    @Binding var styling: ExampleStyling
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Dialog(title: "settings.title") {
            VStack(alignment: .leading, spacing: 1) {
                Text("settings.explain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Toggle("settings.uppercaseHeaders", isOn: $styling.uppercaseSectionHeaders)
                Toggle("settings.boldButtons", isOn: $styling.boldButtons)
                HStack {
                    Spacer()
                    Button("settings.done") { dismiss() }
                }
            }
        }
        .presentationSizing(.form)
    }
}
