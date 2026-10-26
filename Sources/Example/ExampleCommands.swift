//  🖥️ TUI — A Terminal UI framework for Swift
//  ExampleCommands.swift
//
//  The Example's menu bar: the commands it declares on its scene, acting on
//  the app's styling, bound from its state, and on the page through the value
//  ContentView publishes for the scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - The Commands

/// What the Example adds to the menu bar. The bar itself — the app's menu,
/// Edit with Undo, Redo, Cut, Copy and Paste, and Help with its tooltips — is
/// TUI's, from declaring any commands at all; this adds:
///
/// - **Edit:** Find… and Find Next (``TextEditingCommands``), enabled while a
///   text editor has the focus.
/// - **View:** TUI's ``DisplayCommands`` — Palette, Border Style and
///   Control Style, each a submenu of its choices with the current one
///   checked — bound to the app's own palette and control style, which the
///   scene applies; Border Style acts on the appearance manager, and TUI
///   disables it while the Theme page's custom border is in force (the
///   scene's `.appearance(_:)`), which a built-in one would not show through.
///   Then Text Styling, the Example's own: a submenu of two `Toggle`s, each a
///   checked item; then the standard toolbar and sidebar commands.
/// - **Go**, as Finder's: the main menu (disabled on it), and the previous and
///   next demo page.
///
/// The File menu is TUI's: Close (⌘W) and Close All (⌥⌘W), since the Example
/// opens more than one window. With no documents, the Example adds nothing to
/// it.
///
/// **The Go menu's keys.** Finder's Back and Forward are ⌘[ and ⌘], whose
/// Control chords a terminal cannot send: ⌃[ is Escape's byte, and ⌃] one
/// TUI does not read. Of the Control letters a terminal sends as
/// themselves, the Example and TUI already bind A (a list's select all),
/// C, V, X, Z and Y (the clipboard, undo and redo), D, K, R and S (a list's or table's
/// row keys, and the sidebar), F and G (a text editor's find), and N, O and S
/// (the Menus page's ⌘ shortcuts); E keeps a text editor's end of line. So
/// Previous Page is ⌃B, back, and Next Page ⌃T, turn — letters only a text
/// control's Emacs chords use, which give way to an app's shortcut. Main Menu
/// is Escape, the key the pages already go back to it with.
struct ExampleCommands: Commands {
    /// The app's palette, which View ▸ Palette loads a preset into.
    @Binding var palette: CustomizablePalette

    /// The app's styling, which View ▸ Text Styling and Control Style set.
    @Binding var styling: ExampleStyling

    @FocusedBinding(\.examplePage) private var page

    var body: some Commands {
        TextEditingCommands()
        // Declared before the display commands, so it is drawn after them: the
        // newest `before:` addition goes first, as SwiftUI places them.
        CommandGroup(before: .toolbar) {
            Section {
                Menu(L("commands.textStyling")) {
                    Toggle(L("settings.uppercaseHeaders"), isOn: $styling.uppercaseSectionHeaders)
                    Toggle(L("settings.boldButtons"), isOn: $styling.boldButtons)
                }
            }
        }
        DisplayCommands(palette: presetPalette, controlStyle: $styling.controlStyle)
        ToolbarCommands()
        SidebarCommands()
        CommandMenu(L("commands.go")) {
            Button(L("commands.mainMenu")) { page = .menu }
                .keyboardShortcutHint(KeyboardShortcut(.escape, modifiers: []))
                .disabled(page == nil || page == .menu)
            Divider()
            Button(L("commands.previousPage")) { step(-1) }
                .keyboardShortcut("b", modifiers: .control)
                .disabled(page == nil)
            Button(L("commands.nextPage")) { step(1) }
                .keyboardShortcut("t", modifiers: .control)
                .disabled(page == nil)
        }
    }

    /// The app's palette as View ▸ Palette chooses it: a preset chosen is
    /// loaded into the editable palette, as the Theme page's preset picker
    /// loads one.
    private var presetPalette: Binding<any Palette> {
        let palette = $palette
        return Binding(
            get: { palette.wrappedValue },
            set: { palette.wrappedValue = CustomizablePalette(from: $0) })
    }

    /// Moves `offset` pages through the demo list, round the ends.
    private func step(_ offset: Int) {
        guard let current = page else { return }
        let pages = DemoPage.allCases
        let index = pages.firstIndex(of: current) ?? 0
        page = pages[((index + offset) % pages.count + pages.count) % pages.count]
    }
}

// MARK: - What ContentView Publishes

private struct ExamplePageKey: FocusedValueKey {
    typealias Value = Binding<DemoPage>
}

extension FocusedValues {
    /// The page on the screen, which the Go menu moves between.
    var examplePage: Binding<DemoPage>? {
        get { self[ExamplePageKey.self] }
        set { self[ExamplePageKey.self] = newValue }
    }
}
