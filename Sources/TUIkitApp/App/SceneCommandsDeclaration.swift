//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneCommandsDeclaration.swift
//
//  The hook a scene's commands reach the run loop through: TUIkitCommands,
//  which declares them, is built on this module, so here they are opaque.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - What a Scene's Commands Modifier States

/// One commands modifier written on a scene — `.commands`, `.commandsReplaced`
/// or `.commandsRemoved`, TUIkitCommands' — as the run loop gathers it: opaque
/// here, since the module that declares commands is built on this one.
package protocol SceneCommandsDeclaration {
    /// Whether the modifier takes away the commands of the scene it modifies
    /// — those of the modifiers inside it, and the scene's own — as SwiftUI's
    /// `commandsRemoved()` and `commandsReplaced(content:)` do.
    var closesModifiedScene: Bool { get }
}

/// What the scenes' commands modifiers state, gathered by the walk that
/// catalogues the app's scenes (``SceneCatalog``): the app's, every scene's in
/// declaration order, as SwiftUI's main menu has them.
package struct SceneCommands {
    /// The modifiers whose commands count: each scene's innermost first (the
    /// order SwiftUI adds their menus in, measured on macOS 15.8: the session
    /// notes' `O13/probe/menus.swift`), the scenes in declaration order.
    package private(set) var declarations: [any SceneCommandsDeclaration] = []

    /// Whether the scenes' own commands count: a window scene's, which no
    /// modifier outside it took away.
    package private(set) var includesSceneCommands = false

    /// What draws the window's menu bar from what is gathered here, which the
    /// commands modifiers hand over with their declarations; `nil` until one
    /// does.
    private var makeMenuBar: (@MainActor (Self) -> AnyView?)?

    /// No commands.
    init() {}

    /// A window scene's commands before any modifier: its own.
    static var ofWindow: Self {
        var commands = Self()
        commands.includesSceneCommands = true
        return commands
    }

    /// Adds the commands of a scene declared after those gathered so far.
    mutating func append(_ other: Self) {
        declarations += other.declarations
        includesSceneCommands = includesSceneCommands || other.includesSceneCommands
        makeMenuBar = makeMenuBar ?? other.makeMenuBar
    }

    /// Applies `declaration`, a modifier written around the scenes these are
    /// the commands of: what it declares comes after what they declared, and
    /// one that takes their commands away (``SceneCommandsDeclaration/closesModifiedScene``)
    /// first leaves none of theirs, nor their own.
    mutating func modify(
        by declaration: any SceneCommandsDeclaration, makeMenuBar: @escaping @MainActor (Self) -> AnyView?
    ) {
        if declaration.closesModifiedScene {
            declarations = []
            includesSceneCommands = false
        }
        declarations.append(declaration)
        self.makeMenuBar = makeMenuBar
    }

    /// The view the window's menu bar is drawn with, or `nil` for none.
    @MainActor
    func menuBar() -> AnyView? {
        makeMenuBar?(self)
    }
}

// MARK: - The Wrapper Scene

/// The scene a commands modifier makes: TUIkitCommands' modifiers wrap the
/// scene they modify in one, with what they state, and the run loop reads it
/// from the scene's configuration before anything is laid out — the menu bar's
/// row is known before the walk.
package struct _SceneCommandsModifier<Content: Scene>: Scene {
    /// The scene modified.
    let content: Content

    /// What the modifier states.
    let declaration: any SceneCommandsDeclaration

    /// What draws the menu bar from the scene's gathered commands.
    let makeMenuBar: @MainActor (SceneCommands) -> AnyView?

    /// Wraps `content` with `declaration`, drawn by `makeMenuBar`.
    package init(
        content: Content, declaration: any SceneCommandsDeclaration,
        makeMenuBar: @escaping @MainActor (SceneCommands) -> AnyView?
    ) {
        self.content = content
        self.declaration = declaration
        self.makeMenuBar = makeMenuBar
    }

    /// A primitive scene: it renders through `SceneRenderable`.
    package var body: Never { fatalError("_SceneCommandsModifier renders via SceneRenderable") }
}

/// States nothing of a window's own: its commands are the app's, which the
/// catalogue gathers apart (``SceneCommandsModifying``). It is a link in the
/// chain all the same, so the modifiers on either side of it are found.
extension _SceneCommandsModifier: ConfiguringScene {
    func configure(_ configuration: inout SceneConfiguration) {}

    var configuredContent: (any Scene)? { content }
}

extension _SceneCommandsModifier: SceneCommandsModifying {}

/// A scene modifier that declares commands, which the catalogue applies to
/// the commands of the scenes it modifies (``SceneCommands/modify(by:makeMenuBar:)``).
@MainActor
protocol SceneCommandsModifying: ConfiguringScene {
    /// What the modifier states.
    var declaration: any SceneCommandsDeclaration { get }

    /// What draws the menu bar from the app's gathered commands.
    var makeMenuBar: @MainActor (SceneCommands) -> AnyView? { get }
}

extension _SceneCommandsModifier: SceneRenderable {
    /// The commands are read from the configuration before the frame is laid
    /// out; rendering forwards to the wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}
