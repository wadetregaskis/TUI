//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+KeyboardShortcut.swift
//
//  SwiftUI's `Scene.keyboardShortcut`: the key that opens a scene's window —
//  a new one of a window group, a `Window`'s, the `Settings` sheet.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

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
    /// The key that presents the settings panel, as SwiftUI's ⌘, presents
    /// the `Settings` scene: the one that scene's `.keyboardShortcut` states,
    /// ⌘, where it states none or the app declares no `Settings`, or `nil`
    /// where it took the key away or the panel has no tab to show.
    package var settingsShortcut: KeyboardShortcut? {
        guard hasSettings else { return nil }
        if let stated = settingsEntry?.configuration.keyboardShortcut { return stated }
        return KeyboardShortcut(",", modifiers: .command)
    }

    /// File ▸ Close's key, ⌘W, as on macOS.
    package static let closeShortcut = KeyboardShortcut("w", modifiers: .command)

    /// File ▸ Close All's key, ⌥⌘W, as on macOS.
    package static let closeAllShortcut = KeyboardShortcut("w", modifiers: [.command, .option])

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
        in registry: KeyboardShortcutRegistry, commandKey: CommandKeyBinding, matchesCommand: Bool = false,
        disambiguatesKeys: Bool = false
    ) {
        let service = LocalizationService.shared
        var keys: [(shortcut: KeyboardShortcut, title: (() -> String)?, action: () -> Void)] = []
        for entry in entries {
            guard let shortcut = shortcut(of: entry) else { continue }
            let identity = entry.identity
            let title = entry.window.windowTitle?.content ?? entry.window.sceneID
            keys.append((shortcut, title.map { title in { title } }, { [weak self] in self?.openWindow(ofSceneAt: identity) }))
        }
        if let shortcut = settingsShortcut {
            // Named in the list of keys in force only where the terminal can
            // send it: ⌃, has no legacy encoding, and arrives only under the
            // kitty keyboard protocol's disambiguate mode.
            let arrives =
                disambiguatesKeys
                || shortcut.keyEvent(commandKey: commandKey).map(Self.arrivesInLegacyEncoding) ?? false
            keys.append((
                shortcut, arrives ? { service.string(for: LocalizationKey.Menu.settings) } : nil,
                { [weak self] in self?.presentSettings() }
            ))
        }
        // File ▸ Close and Close All, for an app that can have more than one
        // window open. Registered as commands, so a key of the window's own
        // content wins; and they come before a focused text field's Ctrl-W,
        // the word rubout, which gives way to a shortcut on its chord (the
        // owner, 2026-10-29, replacing O9's "⌃W is the field's").
        if opensSeveralWindows {
            // Named only where they'd do something, as their menu items are
            // enabled: otherwise the key is bound and closes nothing, so the list
            // of what's in force leaves it off.
            keys.append((
                Self.closeShortcut,
                canCloseFrontWindow ? { service.string(for: LocalizationKey.Menu.close) } : nil,
                { [weak self] in self?.closeFrontWindow() }
            ))
            keys.append((
                Self.closeAllShortcut,
                windowsCloseAllCloses.isEmpty ? nil : { service.string(for: LocalizationKey.Menu.closeAll) },
                { [weak self] in self?.closeAllWindows() }
            ))
        }
        guard !keys.isEmpty else { return }
        registry.registeringCommands {
            for key in keys {
                guard let resolved = key.shortcut.resolved(commandKey: commandKey) else { continue }
                registry.registerCommand(
                    resolved, commandChord: key.shortcut.commandChord(matching: matchesCommand), title: key.title,
                    action: key.action)
            }
        }
    }

    /// Whether a terminal speaking only its legacy encodings can send
    /// `event`: Control has a byte only with a letter or one of `@ [ \\ ] ^
    /// _` and Space, so Control with a comma, ⌃, the settings key, has none.
    static func arrivesInLegacyEncoding(_ event: KeyEvent) -> Bool {
        guard event.ctrl, case .character(let character) = event.key else { return true }
        return character.isLetter || "@[\\]^_ ".contains(character)
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
