//  🖥️ TUI — A Terminal UI framework for Swift
//  main.swift
//
//  Created by LAYERED.work
//  License: MIT
//  This app demonstrates TUI capabilities through various demo pages.
//  Use the menu to navigate between demos.
//

import Foundation
import TUI

// MARK: - Main App

/// The main example application.
struct ExampleApp: App {
    /// The preset the whole app's palette was loaded from, by its identifier:
    /// kept with `@AppStorage`, so the palette chosen in View ▸ Palette, the
    /// Theme page or with ⇧F2 is the one the next launch starts in. Green
    /// until one is chosen.
    @AppStorage("example.palette") private var paletteID = SystemPalette(.green).id

    /// The palette's colours as the Theme page's pickers edited them this run,
    /// or `nil` before any edit: held as editable `@State`, and kept for the
    /// run only. An edit keeps its preset's identifier, so the next launch
    /// starts in the preset, unedited.
    @State private var editedPalette: CustomizablePalette?

    /// The control style, by the key of its name (`ExampleStyling.controlStyles`):
    /// kept with `@AppStorage`, as the palette is.
    @AppStorage("example.controlStyle") private var controlStyleKey = ExampleStyling.controlStyles[0].key

    /// App-wide styling (tint + text-attribute toggles), edited on the Theme
    /// page. The scene's `.theme` folds the tint into the palette so the app
    /// header and status bar pick it up too; ContentView applies the chrome and
    /// control text styling to the pages. Its control style is the one kept in
    /// `controlStyleKey` (``styling``).
    @State private var stylingThisRun = ExampleStyling()

    /// The whole app's colour palette, applied to the scene with
    /// `.palette(...)`. The Theme page edits it — presets load a
    /// `SystemPalette`'s colours, the colour pickers tweak individual ones — so a
    /// change re-themes every page and the window's bars live: this run's
    /// edit, while it is of the preset kept, else the kept preset.
    /// (App-level state is re-evaluated each frame, so the scene's `.palette`
    /// override stays in sync.)
    private var palette: Binding<CustomizablePalette> {
        let paletteID = $paletteID
        let edited = $editedPalette
        return Binding(
            get: {
                if let palette = edited.wrappedValue, palette.id == paletteID.wrappedValue { return palette }
                let preset = PaletteRegistry.all.first { $0.id == paletteID.wrappedValue } ?? SystemPalette(.green)
                return CustomizablePalette(from: preset)
            },
            set: {
                edited.wrappedValue = $0
                paletteID.wrappedValue = $0.id
            })
    }

    /// The app-wide styling, with the control style kept in `controlStyleKey`.
    private var styling: Binding<ExampleStyling> {
        let thisRun = $stylingThisRun
        let key = $controlStyleKey
        return Binding(
            get: {
                var styling = thisRun.wrappedValue
                styling.controlStyle =
                    ExampleStyling.controlStyles.first { $0.key == key.wrappedValue }?.style ?? .automatic
                return styling
            },
            set: {
                thisRun.wrappedValue = $0
                let style = $0.controlStyle
                key.wrappedValue =
                    ExampleStyling.controlStyles.first { $0.style == style }?.key ?? ExampleStyling.controlStyles[0].key
            })
    }

    var body: some Scene {
        // Three scenes, styled together: the scene modifiers below are written
        // on the group, so each reaches all three — the Inspector and the
        // settings panel are themed as the main window is.
        Group {
            // Titled: the title is the terminal's window or tab title while
            // this window is in front, as the Inspector's is while it is.
            WindowGroup(L("app.windowTitle")) {
                ContentView(palette: palette, styling: styling)
            }
            // A second window, opened over the main one by `openWindow(id:)`
            // (the Menus page, or the menu bar's Window menu).
            Window(L("inspector.title"), id: "inspector") {
                ExampleInspector()
            }
            // The settings panel's first tab: F2, Settings… (⌃,) or a
            // `SettingsLink` presents it, TUI's View and Accessibility after.
            Settings {
                ExampleSettings(styling: styling)
            }
        }
        .theme(Theme(palette: palette.wrappedValue, tint: styling.wrappedValue.tint))
        // Apply the user-built custom border (Theme page) at the *scene* level so
        // it reaches the window's bars too — not just the page content. `nil` (no custom border) defers to the appearance manager, so
        // F3 / the appearance picker keep driving the built-in border.
        .appearance(styling.wrappedValue.customBorder.map {
            Appearance(id: Appearance.ID(rawValue: "custom"), borderStyle: $0)
        })
        // Likewise scene-level: how the window's bars separate themselves from
        // the page is a property of the app's chrome, not of any page — one
        // style for every bar, chosen on the Theme page.
        .windowToolbarStyle(styling.wrappedValue.toolbarStyle.style)
        // How controls draw their faces, apart from the border: scene-level for
        // the same reason, so the bars' buttons follow it too.
        .environment(\.controlStyle, styling.wrappedValue.controlStyle)
        // Where scroll indicators go, beside the content or over it for the
        // pointer: scene-level too, so every page, the Inspector and Settings
        // follow the Theme page's choice.
        .environment(\.scrollIndicatorPlacement, styling.wrappedValue.scrollIndicatorPlacement)
        // The menu bar, on the top row: declaring commands shows it. The app's
        // menu (with Settings…), Edit, Window and Help are TUI's; View and
        // Go add the Example's own. F10 walks its titles and a title's letter opens one, as does a click on a title.
        .commands { ExampleCommands(palette: palette, styling: styling) }
        // What the app menu's About says: a SwiftPM executable has no
        // Info.plist to say it, so the scene does (a TUI modifier).
        // The credits and the copyright break their lines by hand, so they
        // read balanced rather than wrapping raggedly at the alert's width.
        .aboutPanel(
            applicationName: "TUI Example", applicationVersion: tuiVersion,
            copyright: "Copyright © 2026 Frank Gregor & Wade Tregaskis\nMIT License",
            credits: L("about.credits"))
    }
}

// Register the example app's own localized strings with the shared
// LocalizationService before the UI renders, so `L(_:)` resolves them.
registerExampleLocalizations()

// How many entries the menu has, printed and nothing else.
//
// For the PTY smoke walk, which has to know when it has seen every page. The
// number lived in `Tools/Smoke/ci-pty-smoke.sh` as a literal, and a literal
// count of a list someone else maintains only ever drifts one way: two
// scenarios were added to the sibling Stress app and its count was not raised,
// so CI walked 19 of 21 and quietly stopped smoking two pages. Stress already
// answers this from its registry rather than a literal (see the note above
// `scenarioIDs` in its `main.swift`); this is the Example saying the same
// thing about `DemoPage`, which is the only place that actually knows.
if CommandLine.arguments.dropFirst().contains("--pages") {
    print(DemoPage.allCases.count)
    exit(0)
}

// Run the app
await ExampleApp.main()
