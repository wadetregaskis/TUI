//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ExampleCommands.swift
//
//  The Example's menu bar: the commands it declares on its scene, acting on
//  the app's styling, bound from its state, and on the page through the value
//  ContentView publishes for the scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - The Commands

/// What the Example adds to the menu bar. The bar itself — the app's menu,
/// Edit with Undo, Redo, Cut, Copy and Paste, and Help with its tooltips — is
/// TUIkit's, from declaring any commands at all; this adds:
///
/// - **Edit:** Find… and Find Next (``TextEditingCommands``), enabled while a
///   text editor has the focus.
/// - **View:** the app's palette and border style, each a `Picker` and so a
///   submenu of its choices with the current one checked; Text Styling, a
///   submenu of two `Toggle`s, each a checked item; then the standard toolbar
///   and sidebar commands. Border Style is disabled while the Theme page's
///   custom border is in force, which a built-in one would not show through.
/// - **Go**, as Finder's: the main menu (disabled on it), and the previous and
///   next demo page.
///
/// No File menu: an app with no documents has nothing for it, and TUIkit draws
/// a standard menu only when something is in it.
///
/// **The Go menu's keys.** Finder's Back and Forward are ⌘[ and ⌘], whose
/// Control chords a terminal cannot send: ⌃[ is Escape's byte, and ⌃] one
/// TUIkit does not read. Of the Control letters a terminal sends as
/// themselves, the Example and TUIkit already bind A (a list's select all),
/// C, V, X and Z (the clipboard and undo), D, K, R and S (a list's or table's
/// row keys, and the sidebar), F and G (a text editor's find), and N, O and S
/// (the Menus page's ⌘ shortcuts); E keeps a text editor's end of line. So
/// Previous Page is ⌃B, back, and Next Page ⌃T, turn — letters only a text
/// control's Emacs chords use, which give way to an app's shortcut. Main Menu
/// is Escape, the key the pages already go back to it with.
struct ExampleCommands: Commands {
    /// The app's palette, which View ▸ Palette picks a preset into.
    @Binding var palette: CustomizablePalette

    /// The app's styling, which View ▸ Text Styling and Border Style read.
    @Binding var styling: ExampleStyling

    @FocusedBinding(\.examplePage) private var page
    @Environment(\.appearanceManager) private var appearanceManager

    var body: some Commands {
        TextEditingCommands()
        CommandGroup(before: .toolbar) {
            Picker(L("commands.palette"), selection: paletteSelection) {
                ForEach(0..<PaletteRegistry.all.count, id: \.self) { index in
                    Text(verbatim: PaletteRegistry.all[index].name).tag(PaletteRegistry.all[index].id)
                }
            }
            Picker(L("commands.borderStyle"), selection: borderSelection) {
                ForEach(0..<AppearanceRegistry.all.count, id: \.self) { index in
                    Text(verbatim: AppearanceRegistry.all[index].name).tag(AppearanceRegistry.all[index].id)
                }
            }
            .disabled(styling.customBorder != nil)
            Menu(L("commands.textStyling")) {
                Toggle(L("settings.uppercaseHeaders"), isOn: $styling.uppercaseSectionHeaders)
                Toggle(L("settings.boldButtons"), isOn: $styling.boldButtons)
            }
            Divider()
        }
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

    /// The preset the palette is, by its id; choosing one loads it, as the
    /// Theme page's preset picker does.
    private var paletteSelection: Binding<String> {
        let palette = $palette
        return Binding(
            get: { palette.wrappedValue.id },
            set: { id in
                guard let preset = PaletteRegistry.all.first(where: { $0.id == id }) else { return }
                palette.wrappedValue = CustomizablePalette(from: preset)
            })
    }

    /// The built-in border style in force, by its id, as the Theme page's
    /// appearance picker binds it.
    private var borderSelection: Binding<String> {
        let manager = appearanceManager
        return Binding(
            get: { manager?.current.id ?? "" },
            set: { id in
                guard let appearance = AppearanceRegistry.all.first(where: { $0.id == id }) else { return }
                manager?.setCurrent(appearance)
            })
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
