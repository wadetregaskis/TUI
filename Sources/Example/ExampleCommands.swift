//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ExampleCommands.swift
//
//  The Example's menu bar: the commands it declares on its scene, acting on
//  the page through the values ContentView publishes for the scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - The Commands

/// What the Example adds to the menu bar. The bar itself — the app's menu,
/// Edit with Undo, Redo, Cut, Copy and Paste — is TUIkit's, from declaring any
/// commands at all; this adds:
///
/// - **File:** the page navigation — back to the main menu, and the previous
///   and next demo page — in place of macOS's New and Open, which an app with
///   no documents has no use for.
/// - **Edit:** Find… and Find Next (``TextEditingCommands``), for the text
///   editor's find bar.
/// - **View:** the palette and border cycling F2 and F3 do, and the standard
///   toolbar and sidebar commands.
///
/// It reads the page through ``FocusedValues/examplePage``, which `ContentView`
/// publishes for the scene (`focusedSceneValue`), so a command acts on what is
/// on the screen this frame.
struct ExampleCommands: Commands {
    @FocusedBinding(\.examplePage) private var page
    @FocusedValue(\.exampleThemeActions) private var themeActions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("commands.mainMenu")) { page = .menu }
                .disabled(page == nil || page == .menu)
            Button(L("commands.previousPage")) { step(-1) }
                .disabled(page == nil)
            Button(L("commands.nextPage")) { step(1) }
                .disabled(page == nil)
        }
        TextEditingCommands()
        CommandGroup(before: .toolbar) {
            Button(L("commands.nextPalette")) { themeActions?.nextPalette() }
                .disabled(themeActions == nil)
            Button(L("commands.nextBorder")) { themeActions?.nextBorder() }
                .disabled(themeActions == nil)
            Divider()
        }
        ToolbarCommands()
        SidebarCommands()
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

/// The theme actions F2 and F3 take, which the View menu offers too.
struct ExampleThemeActions {
    /// Loads the next built-in palette.
    let nextPalette: () -> Void

    /// Cycles the border appearance.
    let nextBorder: () -> Void
}

private struct ExamplePageKey: FocusedValueKey {
    typealias Value = Binding<DemoPage>
}

private struct ExampleThemeActionsKey: FocusedValueKey {
    typealias Value = ExampleThemeActions
}

extension FocusedValues {
    /// The page on the screen, which the File menu moves between.
    var examplePage: Binding<DemoPage>? {
        get { self[ExamplePageKey.self] }
        set { self[ExamplePageKey.self] = newValue }
    }

    /// The theme actions the View menu offers.
    var exampleThemeActions: ExampleThemeActions? {
        get { self[ExampleThemeActionsKey.self] }
        set { self[ExampleThemeActionsKey.self] = newValue }
    }
}
