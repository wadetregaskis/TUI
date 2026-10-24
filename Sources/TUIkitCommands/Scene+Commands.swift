//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+Commands.swift
//
//  The scene modifiers that declare commands, and so the menu bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitApp
import TUIkitFoundation

// MARK: - Public Modifiers

extension Scene {
    /// Adds commands to the scene — mirrors SwiftUI's
    /// `Scene.commands(content:)`.
    ///
    /// A scene that declares commands has a menu bar, on the window's top row:
    /// the app's menu (About and Quit), the standard menus that have something
    /// in them (File, Edit — Undo, Redo, Cut, Copy and Paste — Format, View,
    /// Window and Help), and the app's own ``CommandMenu``s between View and
    /// Window, in order of declaration.
    /// Each ``CommandGroup`` goes into its standard group of its standard
    /// menu, delimited from the next group by a separator.
    ///
    /// A command's keyboard shortcut works whether its menu is open or not.
    /// A shortcut the window's content registers on the same key is asked
    /// first, as a key equivalent goes to the window before the menu bar.
    ///
    /// ```swift
    /// WindowGroup { NotesView() }
    ///     .commands {
    ///         CommandGroup(replacing: .newItem) {
    ///             Button("New Note") { … }.keyboardShortcut("n")
    ///         }
    ///         CommandMenu("Note") { … }
    ///     }
    /// ```
    ///
    /// Commands written on several modifiers add up, the innermost first.
    ///
    /// - Parameter content: A ``CommandsBuilder`` that creates the commands.
    /// - Returns: A scene that adds the commands.
    public func commands<Content: Commands>(@CommandsBuilder content: () -> Content) -> some Scene {
        _SceneCommandsModifier(content: self, commands: content(), closes: false)
    }

    /// Removes all commands defined by the modified scene — mirrors SwiftUI's
    /// `Scene.commandsRemoved()`.
    ///
    /// The commands written on the scene inside this modifier no longer
    /// count, and nor do the scene's own: the app's menu's About and Quit and
    /// the Edit menu's Undo, Redo, Cut, Copy and Paste. Commands written
    /// outside it still do, as
    /// SwiftUI composes them on macOS (measured on macOS 15.8:
    /// `Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`, where `.commands { A }.commandsRemoved()`
    /// left no menu of A's or of the app's, and `.commandsRemoved().commands
    /// { A }` left A's alone). With nothing left, the scene has no menu bar.
    ///
    /// - Returns: A scene that excludes any commands defined by its children.
    public func commandsRemoved() -> some Scene {
        _SceneCommandsModifier(content: self, commands: nil, closes: true)
    }

    /// Replaces all commands defined by the modified scene with the commands
    /// from the builder — mirrors SwiftUI's `Scene.commandsReplaced(content:)`.
    ///
    /// What ``commandsRemoved()`` takes away, these replace: the commands
    /// written inside this modifier and the scene's own.
    ///
    /// - Parameter content: A ``CommandsBuilder`` whose output will be used to
    ///   replace the commands normally provided by the modified scene.
    /// - Returns: A scene that replaces any commands defined by its children
    ///   with alternative content.
    public func commandsReplaced<Content: Commands>(@CommandsBuilder content: () -> Content) -> some Scene {
        _SceneCommandsModifier(content: self, commands: content(), closes: true)
    }
}

// MARK: - The Declaration

/// What one commands modifier states: its commands, if any, and whether it
/// takes away the commands of the scene it modifies.
struct CommandsDeclaration: SceneCommandsDeclaration {
    /// The commands it adds, or `nil` for one that only takes away.
    let commands: (any Commands)?

    /// Whether it takes away the modified scene's commands.
    let closesModifiedScene: Bool
}

extension _SceneCommandsModifier {
    /// The scene `content`, with `commands` declared on it; `closes` takes
    /// away what `content` declared.
    @MainActor
    init(content: Content, commands: (any Commands)?, closes: Bool) {
        self.init(
            content: content, declaration: CommandsDeclaration(commands: commands, closesModifiedScene: closes),
            makeMenuBar: _MenuBarCore.menuBar(for:))
    }
}
