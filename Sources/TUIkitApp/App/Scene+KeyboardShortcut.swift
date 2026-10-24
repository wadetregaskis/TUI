//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+KeyboardShortcut.swift
//
//  SwiftUI's `Scene.keyboardShortcut`: the key that opens a scene's window —
//  a new one of a window group, a `Window`'s, the `Settings` sheet.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Public Modifiers

extension Scene {
    /// Defines a keyboard shortcut for opening new scene windows — mirrors
    /// SwiftUI's `Scene.keyboardShortcut(_:)`.
    ///
    /// On a `WindowGroup` the key opens a new window of the group, on a
    /// `Window` its window or brings it to the front, on `Settings` the
    /// settings sheet, in place of its ⌘,. It works whether or not the app has
    /// a menu bar, and a shortcut the window's content registers on the same
    /// key is asked first, as a command's is. `nil` takes a scene's default
    /// key away (`Settings`'s ⌘,).
    ///
    /// - Parameter shortcut: The keyboard shortcut, or `nil` for none.
    /// - Returns: A scene that opens on the key.
    public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some Scene {
        _SceneKeyboardShortcut(content: self, shortcut: shortcut)
    }

    /// Defines a keyboard shortcut for opening new scene windows — mirrors
    /// SwiftUI's `Scene.keyboardShortcut(_:modifiers:localization:)`.
    ///
    /// - Parameters:
    ///   - key: The key equivalent the person presses.
    ///   - modifiers: The modifier keys, by default ⌘, through the scene's
    ///     `commandKey`.
    ///   - localization: How the shortcut is localized.
    /// - Returns: A scene that opens on the key.
    public func keyboardShortcut(
        _ key: KeyEquivalent, modifiers: EventModifiers = .command,
        localization: KeyboardShortcut.Localization = .automatic
    ) -> some Scene {
        _SceneKeyboardShortcut(
            content: self, shortcut: KeyboardShortcut(key, modifiers: modifiers, localization: localization))
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that states the key its scene opens on.
internal struct _SceneKeyboardShortcut<Content: Scene>: Scene {
    let content: Content
    let shortcut: KeyboardShortcut?

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_SceneKeyboardShortcut renders via SceneRenderable") }
}

extension _SceneKeyboardShortcut: ConfiguringScene {
    /// The modifier closest to the scene wins, as every scene modifier's.
    func configure(_ configuration: inout SceneConfiguration) {
        configuration.keyboardShortcut = .some(shortcut)
    }

    var configuredContent: (any Scene)? { content }
}

extension _SceneKeyboardShortcut: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}

// MARK: - Registering the Keys

extension ScenePresenter {
    /// The key that presents the `Settings` scene: the one its
    /// `.keyboardShortcut` states, SwiftUI's ⌘, where it states none, or
    /// `nil` where it took the key away or the app declares no `Settings`.
    package var settingsShortcut: KeyboardShortcut? {
        guard let settings = overlayEntries.first(where: { $0.scene.isSettings }) else { return nil }
        return settings.configuration.keyboardShortcut ?? KeyboardShortcut(",", modifiers: .command)
    }

    /// The key that opens the window scene `entry`, if its
    /// `.keyboardShortcut` states one. A window scene has no key by default:
    /// SwiftUI's window group has ⌘N, through the File menu's New Window,
    /// which a terminal app's menu bar does not have (decisions O9, B-O9-12).
    func shortcut(of entry: SceneCatalog.WindowEntry) -> KeyboardShortcut? {
        // A stated `nil` and none stated alike: no key.
        entry.configuration.keyboardShortcut.flatMap { $0 }
    }

    /// Registers the scenes' keys into `registry` as the menu bar's commands
    /// register theirs, so the window's content keeps any it registered on
    /// the same key: each opens its scene, whether or not the app shows a
    /// menu bar, whose items only show them.
    func registerSceneShortcuts(
        in registry: KeyboardShortcutRegistry, commandKey: CommandKeyBinding, matchesCommand: Bool = false
    ) {
        var keys: [(shortcut: KeyboardShortcut, action: () -> Void)] = []
        for entry in entries {
            guard let shortcut = shortcut(of: entry) else { continue }
            let identity = entry.identity
            keys.append((shortcut, { [weak self] in self?.openWindow(ofSceneAt: identity) }))
        }
        if let shortcut = settingsShortcut {
            keys.append((shortcut, { [weak self] in self?.presentSettings() }))
        }
        guard !keys.isEmpty else { return }
        registry.registeringCommands {
            for key in keys {
                guard let resolved = key.shortcut.resolved(commandKey: commandKey) else { continue }
                registry.registerCommand(
                    resolved, commandChord: key.shortcut.commandChord(matching: matchesCommand), action: key.action)
            }
        }
    }

    /// Opens a window of the scene at `identity` as its key does: brings a
    /// `Window`'s to the front, or opens it; opens a new one of a group.
    func openWindow(ofSceneAt identity: ViewIdentity) {
        guard let entry = entries.first(where: { $0.identity == identity }) else { return }
        if entry.window.opensOneWindow, let open = windows.first(where: { $0.sceneKey == identity }) {
            bringToFront(open.serial)
        } else {
            openNewWindow(of: entry)
        }
    }
}
