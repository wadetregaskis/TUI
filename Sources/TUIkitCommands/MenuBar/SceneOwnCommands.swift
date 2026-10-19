//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneOwnCommands.swift
//
//  What the standard groups hold before an app changes them: the commands a
//  terminal app has.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
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
/// | `appTermination` | Quit *app* | the quit key, after the menu closes | `StatusBarState.quitShortcut` |
/// | `undoRedo` | Undo, Redo | the app's `UndoManager`; disabled with nothing to undo or redo | the scene's undo and redo keys |
/// | `pasteboard` | Cut, Copy, Paste | ⌘X, ⌘C, ⌘V to the focused view, after the menu closes | the same, through `commandKey` |
///
/// The keys pressed "after the menu closes" go once the frame that closed it
/// has given the page its focus back (``KeysAfterFrame``): a menu holds the
/// focus and the keyboard while it is open, and these act on the focused view.
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
        case .appTermination:
            let quit = environment.statusBar?.quitShortcut ?? .q
            let title = LocalizedStringKey.substituting(
                [_MenuBarCore.appName], into: service.string(for: LocalizationKey.Menu.quitApp))
            return Self.items("quit") {
                Button(title) { keys?.press(quit.keyEvent) }
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
