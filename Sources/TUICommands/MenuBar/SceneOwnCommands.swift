//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneOwnCommands.swift
//
//  What the standard groups hold before an app changes them: the commands a
//  terminal app has.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIApp
import TUIFoundation

/// The scene's own commands — what TUI puts in the standard groups before
/// an app's ``CommandGroup`` adds to or replaces them, as a `WindowGroup`'s own
/// are on macOS (measured on macOS 15.8, `Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`:
/// the app's menu holds About and Quit, the Edit menu Undo, Redo, Cut, Copy and
/// Paste). `commandsRemoved()` takes them away, as there.
///
/// Each does what a key does — the menu bar is a way to them, never the only
/// one — and shows that key, without binding it again
/// (`View.keyboardShortcutHint(_:)`):
///
/// | Group | Item | What choosing it does | Key shown |
/// |---|---|---|---|
/// | `appInfo` | About *app* | an alert naming the app, with its version, credits and copyright where the scene states them (`Scene.aboutPanel`) or its Info.plist has them | — |
/// | `appSettings` | Settings… | presents the `Settings` scene (`openSettings`), where the app declares one | the scene's key: ⌘, unless its `.keyboardShortcut` says otherwise |
/// | `appTermination` | Quit *app* | quits as the quit key does, after the menu closes | `StatusBarState.quitShortcut` |
/// | `undoRedo` | Undo, Redo | the app's `UndoManager`; disabled with nothing to undo or redo | the scene's undo and redo keys |
/// | `pasteboard` | Cut, Copy, Paste | ⌘X, ⌘C, ⌘V to the focused view, after the menu closes | the same, through `commandKey` |
/// | `help` | Show Tooltips; Show All Tooltips | whether tooltips show at all; every tooltip on the screen at once (`TooltipState`); each disabled where no view on the screen has help | —; ⌥ and the help key (⌥?), and Shift-F1, the chain's last resort, where Option does not arrive |
/// | `toolbar` | Customize Toolbar… | opens the customization panel of the page's customizable toolbar (`toolbar(id:content:)`), as its right-click does; only while the page shows one, and not where the commands offer it themselves (`ToolbarCommands`) | — |
/// | `saveItem` | Close; Close All | closes the window in front; every window that may close but the one at the back; each disabled where it would close nothing (the Window menu's rule) | ⌘W; ⌥⌘W — a focused text field keeps Ctrl-W, its word rubout |
/// | `windowArrangement` | Close Window | closes the window in front; disabled where the person may not: the last, one whose content disabled its dismissal, one showing a sheet | Escape |
/// | `windowList` | each open window, the one in front checked | brings it to the front | — |
/// | `singleWindowList` | each `Window` scene | opens it, or brings its window to the front | its `.keyboardShortcut`, if it states one |
///
/// Customize Toolbar… is TUI's: macOS's View menu offers it only with
/// `ToolbarCommands` (measured on macOS 15.8:
/// `Tools/SwiftUIProbes/The menu bar (O13)/toolbarId.out`), leaving the
/// toolbar's context menu as the way there. Here the keyboard reaches that
/// menu only while one of the bar's items has the focus (Shift+F10), so the
/// menu bar is the keyboard's way to the panel wherever a page shows a
/// customizable toolbar (owner ruling CUSTOMIZE-CHORD, 2026-10-29: no chord of
/// its own).
///
/// The Window menu's three groups are filled only for an app that can have
/// more than one window open — more than one window scene, or a window group
/// `openWindow` or a key opens more windows of: one with a single window has
/// nothing to list.
/// The scenes' keys — Settings…'s ⌘, and any a scene's `.keyboardShortcut`
/// states — are bound by the scene presenter, menu bar or none, through
/// `commandKey`.
///
/// The keys pressed "after the menu closes" go once the frame that closed it
/// has given the page its focus back (``KeysAfterFrame``): a menu holds the
/// focus and the keyboard while it is open, and these act on the focused view.
/// Quit presses no key — through the whole chain, the quit key reached the
/// focused view first, and a focused text field typed it — but asks for the
/// quit the key asks for: through the status bar, where it may be confirmed
/// first or not allowed at all, as with the key.
@MainActor
struct SceneOwnCommands {
    /// Shows the About alert.
    let showAbout: () -> Void

    /// Whether the scene's commands offer Customize Toolbar… themselves
    /// (``ToolbarCommands``), so the toolbar group has none of its own.
    let commandsOfferCustomizeToolbar: Bool

    /// What `group` holds before an edit, where the bar renders in `context`;
    /// `nil` for a group TUI leaves empty.
    func items(for group: CommandGroupPlacement.Group, context: RenderContext) -> CommandItems? {
        let environment = context.environment
        let keys = environment.keysAfterFrame
        let service = LocalizationService.shared
        switch group {
        case .appInfo:
            return Self.items("about") { Button(environment.resolvedAboutPanel.aboutTitle, action: showAbout) }
        case .appSettings:
            return settingsItems(environment)
        case .windowArrangement, .windowList, .singleWindowList:
            return environment.scenePresenter.flatMap {
                windowItems(group, presenter: $0, appName: environment.resolvedAboutPanel.name)
            }
        case .saveItem:
            return environment.scenePresenter.flatMap(closeItems)
        case .appTermination:
            let quit = environment.statusBar?.quitShortcut ?? .q
            let title = LocalizedStringKey.substituting(
                [environment.resolvedAboutPanel.name], into: service.string(for: LocalizationKey.Menu.quitApp))
            return Self.items("quit") {
                Button(title) { keys?.quit() }
                    .keyboardShortcutHint(quit.keyboardShortcut)
            }
        case .undoRedo:
            return undoItems(environment)
        case .help:
            return helpItems(environment)
        case .toolbar:
            return customizeToolbarItems(environment)
        case .pasteboard:
            return Self.items("pasteboard") {
                pressing("x", title: service.string(for: LocalizationKey.Menu.cut), environment)
                pressing("c", title: service.string(for: LocalizationKey.Button.copy), environment)
                pressing("v", title: service.string(for: LocalizationKey.Button.paste), environment)
            }
        default:
            return nil
        }
    }

    /// Settings…, presenting the app's `Settings` scene, showing its key; none
    /// for an app that declares no `Settings` scene.
    private func settingsItems(_ environment: EnvironmentValues) -> CommandItems? {
        let openSettings = environment.openSettings
        guard openSettings.isAvailable else { return nil }
        let title = LocalizationService.shared.string(for: LocalizationKey.Menu.settings)
        // The `Settings` scene's key — ⌘, unless its `.keyboardShortcut` says
        // otherwise — which the presenter binds, menu bar or none.
        let shortcut = environment.scenePresenter?.settingsShortcut
        return Self.items("settings") {
            Button(title) { openSettings() }
                .keyboardShortcutHint(shortcut)
        }
    }

    /// View ▸ Customize Toolbar…, while the page shows a customizable toolbar
    /// and the commands do not offer it themselves: ``ToolbarCommands``' item.
    private func customizeToolbarItems(_ environment: EnvironmentValues) -> CommandItems? {
        guard !commandsOfferCustomizeToolbar, let chrome = environment.windowChrome,
            !chrome.customizableToolbars.isEmpty
        else { return nil }
        return Self.items("customize-toolbar") { CustomizeToolbarCommand.item(chrome) }
    }

    /// File ▸ Close and Close All, for an app that can open more than one
    /// window: the window in front, and every window that may close but the
    /// one at the back, on ⌘W and ⌥⌘W, which the presenter binds. They come
    /// before a focused text field's Ctrl-W, the word rubout, as every Command
    /// chord does (the owner, 2026-10-29, replacing O9).
    private func closeItems(_ presenter: ScenePresenter) -> CommandItems? {
        guard presenter.opensSeveralWindows else { return nil }
        let service = LocalizationService.shared
        return Self.items("close") {
            Button(service.string(for: LocalizationKey.Menu.close)) { presenter.closeFrontWindow() }
                .keyboardShortcutHint(ScenePresenter.closeShortcut)
                .disabled(!presenter.canCloseFrontWindow)
            Button(service.string(for: LocalizationKey.Menu.closeAll)) { presenter.closeAllWindows() }
                .keyboardShortcutHint(ScenePresenter.closeAllShortcut)
                .disabled(presenter.windowsCloseAllCloses.isEmpty)
        }
    }

    /// The Window menu's groups: Close Window, the open windows and the
    /// `Window` scenes — for an app that can open more than one window.
    private func windowItems(
        _ group: CommandGroupPlacement.Group, presenter: ScenePresenter, appName: String
    ) -> CommandItems? {
        guard presenter.opensSeveralWindows else { return nil }
        switch group {
        case .windowArrangement:
            let title = LocalizationService.shared.string(for: LocalizationKey.Menu.closeWindow)
            return Self.items("close-window") {
                Button(title) { presenter.closeFrontWindow() }
                    .keyboardShortcutHint(KeyboardShortcut(.escape, modifiers: []))
                    .disabled(!presenter.canCloseFrontWindow)
            }
        case .windowList:
            let windows = presenter.listedWindows
            return Self.items("window-list") {
                ForEach(windows, id: \.serial) { window in
                    Toggle(
                        window.title ?? appName,
                        isOn: Binding(
                            get: { window.isFront },
                            set: { if $0 { presenter.showWindow(window.serial) } }))
                }
            }
        case .singleWindowList:
            let scenes = presenter.listedScenes
            guard !scenes.isEmpty else { return nil }
            return Self.items("single-window-list") {
                ForEach(scenes, id: \.id) { scene in
                    Button(scene.title ?? scene.id) { presenter.openScene(scene.id) }
                        .keyboardShortcutHint(scene.shortcut)
                }
            }
        default:
            return nil
        }
    }

    /// Undo and Redo: the app's undo manager's, each disabled with no step to
    /// take, titled with the step's action name as macOS titles them.
    private func undoItems(_ environment: EnvironmentValues) -> CommandItems? {
        guard let undoManager = environment.undoManager else { return nil }
        let keys = environment.statusBar?.undoKeys
        // The key named follows the focus, as the status bar's does: a text
        // field's own ⌃Y yanks (FB9-REDO).
        let focus = environment.focusManager?.currentFocused as? any TextInputFocusHandler
        let service = LocalizationService.shared
        func title(_ verb: String, _ action: String) -> String { action.isEmpty ? verb : "\(verb) \(action)" }
        let undo = title(service.string(for: LocalizationKey.Menu.undo), undoManager.undoActionName)
        let redo = title(service.string(for: LocalizationKey.Menu.redo), undoManager.redoActionName)
        return Self.items("undo") {
            Button(undo) { _ = UndoCommand.undo.perform(on: undoManager) }
                .keyboardShortcutHint(keys?.shortcut(for: .undo, sparing: focus))
                .disabled(!undoManager.canUndo)
            Button(redo) { _ = UndoCommand.redo.perform(on: undoManager) }
                .keyboardShortcutHint(keys?.shortcut(for: .redo, sparing: focus))
                .disabled(!undoManager.canRedo)
        }
    }

    /// Help ▸ Show Tooltips, a check: whether tooltips show at all; and Show
    /// All Tooltips (Hide All Tooltips while they show), every tooltip on the
    /// screen at once, showing the help key with Option, which does the same
    /// (`TooltipState.menuTrigger`). Each disabled while no view on the screen
    /// has help — Show All, too, while tooltips are off — except to take back
    /// what it chose: tooltips off, or all of them showing. None outside a
    /// running app, which has no tooltips.
    private func helpItems(_ environment: EnvironmentValues) -> CommandItems? {
        guard let tooltips = environment.tooltipState else { return nil }
        let service = LocalizationService.shared
        let hasHelp = tooltips.hasHelpOnScreen
        let showsAll = tooltips.showsAllTooltips
        let shows = Binding(get: { tooltips.showsTooltips }, set: { tooltips.showsTooltips = $0 })
        var showAllKey: KeyboardShortcut?
        if case .character(let character) = tooltips.helpKey {
            showAllKey = KeyboardShortcut(KeyEquivalent(character), modifiers: .option)
        }
        return Self.items("help") {
            Toggle(service.string(for: LocalizationKey.Menu.showTooltips), isOn: shows)
                .disabled(!hasHelp && tooltips.showsTooltips)
            Button(service.string(for: showsAll ? LocalizationKey.Menu.hideAllTooltips : .showAllTooltips)) {
                tooltips.toggleShowsAllTooltips()
            }
            .keyboardShortcutHint(showAllKey)
            .disabled(!showsAll && !(hasHelp && tooltips.showsTooltips))
        }
    }

    /// An item that presses ⌘ and `character` — through the scene's
    /// `commandKey` — once the menu has closed, showing that key.
    private func pressing(_ character: Character, title: String, _ environment: EnvironmentValues) -> some View {
        let shortcut = KeyboardShortcut(KeyEquivalent(character), modifiers: .command)
        let event = shortcut.keyEvent(commandKey: environment.commandKey)
        let keys = environment.keysAfterFrame
        return Button(title) { event.map { keys?.press($0) } }
            .keyboardShortcutHint(shortcut)
            .disabled(event == nil)
    }

    /// `content` as a group's own items, keyed apart from every declaration's.
    private static func items<Content: View>(_ key: String, @ViewBuilder _ content: () -> Content) -> CommandItems {
        let content = content()
        return CommandItems(
            view: AnyView(content), children: { resolveChildViews(from: content, context: $0) }, key: "scene-" + key)
    }
}
