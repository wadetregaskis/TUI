//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneOwnCommands.swift
//
//  What the standard groups hold before an app changes them: the commands a
//  terminal app has.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitApp
import TUIkitFoundation

/// The scene's own commands — what TUIkit puts in the standard groups before
/// an app's ``CommandGroup`` adds to or replaces them, as a `WindowGroup`'s own
/// are on macOS (measured on macOS 15.8, session notes `O13/probe/menus.swift`:
/// the app's menu holds About and Quit, the Edit menu Undo, Redo, Cut, Copy and
/// Paste). `commandsRemoved()` takes them away, as there.
///
/// Each does what a key does — the menu bar is a way to them, never the only
/// one — and shows that key, without binding it again
/// (`View.keyboardShortcutHint(_:)`):
///
/// | Group | Item | What choosing it does | Key shown |
/// |---|---|---|---|
/// | `appInfo` | About *app* | an alert naming the app, and its version where it is bundled | — |
/// | `appSettings` | Settings… | presents the `Settings` scene (`openSettings`), where the app declares one | the scene's key: ⌘, unless its `.keyboardShortcut` says otherwise |
/// | `appTermination` | Quit *app* | quits as the quit key does, after the menu closes | `StatusBarState.quitShortcut` |
/// | `undoRedo` | Undo, Redo | the app's `UndoManager`; disabled with nothing to undo or redo | the scene's undo and redo keys |
/// | `pasteboard` | Cut, Copy, Paste | ⌘X, ⌘C, ⌘V to the focused view, after the menu closes | the same, through `commandKey` |
/// | `windowArrangement` | Close Window | closes the window in front; disabled for the last | Escape |
/// | `windowList` | each open window, the one in front checked | brings it to the front | — |
/// | `singleWindowList` | each `Window` scene | opens it, or brings its window to the front | its `.keyboardShortcut`, if it states one |
///
/// The Window menu's three groups are filled only for an app that declares
/// more than one window scene: one with a single window has nothing to list.
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

    /// What `group` holds before an edit, where the bar renders in `context`;
    /// `nil` for a group TUIkit leaves empty.
    func items(for group: CommandGroupPlacement.Group, context: RenderContext) -> CommandItems? {
        let environment = context.environment
        let keys = environment.keysAfterFrame
        let service = LocalizationService.shared
        switch group {
        case .appInfo:
            return Self.items("about") { Button(_MenuBar.aboutTitle, action: showAbout) }
        case .appSettings:
            return settingsItems(environment)
        case .windowArrangement, .windowList, .singleWindowList:
            return environment.scenePresenter.flatMap { windowItems(group, presenter: $0) }
        case .appTermination:
            let quit = environment.statusBar?.quitShortcut ?? .q
            let title = LocalizedStringKey.substituting(
                [_MenuBarCore.appName], into: service.string(for: LocalizationKey.Menu.quitApp))
            return Self.items("quit") {
                Button(title) { keys?.quit() }
                    .keyboardShortcutHint(quit.keyboardShortcut)
            }
        case .undoRedo:
            return undoItems(environment)
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

    /// The Window menu's groups: Close Window, the open windows and the
    /// `Window` scenes — for an app that can open more than one window.
    private func windowItems(_ group: CommandGroupPlacement.Group, presenter: ScenePresenter) -> CommandItems? {
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
                        window.title ?? _MenuBarCore.appName,
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
        let service = LocalizationService.shared
        func title(_ verb: String, _ action: String) -> String { action.isEmpty ? verb : "\(verb) \(action)" }
        let undo = title(service.string(for: LocalizationKey.Menu.undo), undoManager.undoActionName)
        let redo = title(service.string(for: LocalizationKey.Menu.redo), undoManager.redoActionName)
        return Self.items("undo") {
            Button(undo) { _ = UndoCommand.undo.perform(on: undoManager) }
                .keyboardShortcutHint(keys?.shortcut(for: .undo))
                .disabled(!undoManager.canUndo)
            Button(redo) { _ = UndoCommand.redo.perform(on: undoManager) }
                .keyboardShortcutHint(keys?.shortcut(for: .redo))
                .disabled(!undoManager.canRedo)
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
