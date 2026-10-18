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

/// What a scene's commands modifiers state, gathered with the rest of its
/// configuration (``SceneConfiguration``).
package struct SceneCommands {
    /// The modifiers whose commands count, innermost first: the order SwiftUI
    /// adds their menus in (measured on macOS 15.8: the session notes'
    /// `O13/probe/menus.swift`).
    package private(set) var declarations: [any SceneCommandsDeclaration] = []

    /// Whether the scene's own commands count: not once a modifier outside
    /// them took them away.
    package private(set) var includesSceneCommands = true

    /// What draws the window's menu bar from what is gathered here, which the
    /// commands modifiers hand over with their declarations; `nil` until one
    /// does.
    private var makeMenuBar: (@MainActor (Self) -> AnyView?)?

    /// Whether a modifier outside the one gathered next took away what is
    /// inside it.
    private var isClosed = false

    /// Gathers `declaration`, from a modifier inside every one gathered so far
    /// (the walk goes from the outside in).
    mutating func gather(
        _ declaration: any SceneCommandsDeclaration, makeMenuBar: @escaping @MainActor (Self) -> AnyView?
    ) {
        guard !isClosed else { return }
        declarations.insert(declaration, at: 0)
        self.makeMenuBar = makeMenuBar
        if declaration.closesModifiedScene {
            isClosed = true
            includesSceneCommands = false
        }
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

extension _SceneCommandsModifier: ConfiguringScene {
    func configure(_ configuration: inout SceneConfiguration) {
        configuration.commands.gather(declaration, makeMenuBar: makeMenuBar)
    }

    var configuredContent: (any Scene)? { content }
}

extension _SceneCommandsModifier: SceneRenderable {
    /// The commands are read from the configuration before the frame is laid
    /// out; rendering forwards to the wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}
