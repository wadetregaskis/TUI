//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneCatalog.swift
//
//  The app's scenes, gathered from its body each frame: each window scene
//  with what the modifiers around it configure, and the commands of them all.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Catalog

/// The scenes an app's `body` declares this frame, in declaration order, each
/// with what the modifiers written around it state, gathered in one walk of the
/// scene tree.
///
/// A modifier written on several scenes at once — on a `Group`, or on a custom
/// scene whose `body` is a block of them — states its part for each: the walk
/// carries what the modifiers outside a scene configured down into every scene
/// inside them, and each scene's modifiers write over that, the closest to the
/// content winning, as in one scene's chain (``SceneConfiguration``).
///
/// The commands are the app's, not a scene's: every scene's, in declaration
/// order, as SwiftUI's main menu has them (measured on macOS 15.8 with the
/// session notes' `O9/probe/scenes.swift`: a window group's, a `Window`'s and
/// a `Settings` scene's command menus all stand in the main menu, in that
/// order).
@MainActor
struct SceneCatalog {
    /// One window scene: a ``WindowGroup`` or a ``Window``, whose windows the
    /// run loop draws filling the terminal.
    struct WindowEntry {
        /// The scene, at the end of its modifier chain.
        let window: any WindowScene

        /// What the modifiers around it configure.
        let configuration: SceneConfiguration

        /// Which of each container's scenes leads to it, from the root: what
        /// the run loop draws it by (``SceneRenderTarget``).
        let path: [Int]

        /// The identity it is drawn at.
        let identity: ViewIdentity
    }

    /// The window scenes, in declaration order.
    private(set) var windows: [WindowEntry] = []

    /// One scene shown over the window in front rather than as a window: a
    /// `Settings` scene, an alert scene (``OverlayScene``).
    struct OverlayEntry {
        /// The scene, at the end of its modifier chain.
        let scene: any OverlayScene

        /// What the modifiers around it configure.
        let configuration: SceneConfiguration

        /// Its place in the body, which its presentation's state is kept
        /// under.
        let identity: ViewIdentity
    }

    /// The overlay scenes, in declaration order.
    private(set) var overlays: [OverlayEntry] = []

    /// The commands of every scene, in declaration order: what the menu bar is
    /// drawn from.
    private(set) var commands = SceneCommands()

    /// Gathers what `scene`, drawn at `identity`, declares.
    init(_ scene: any Scene, identity: ViewIdentity) {
        commands = walk(scene, configuration: SceneConfiguration(), path: [], identity: identity)
    }

    /// The window scene the app opens at launch — the first, as on macOS — as
    /// the run loop draws it, or `nil` where the app declares none.
    var launchTarget: SceneRenderTarget? {
        windows.first.map { SceneRenderTarget(path: $0.path) }
    }

    /// Walks `scene` and what it holds, configured by what the modifiers
    /// outside it stated, and returns the commands they declare.
    private mutating func walk(
        _ scene: any Scene, configuration: SceneConfiguration, path: [Int], identity: ViewIdentity
    ) -> SceneCommands {
        let scene = scene.primitiveScene
        if let container = scene as? any SceneContainer {
            var commands = SceneCommands()
            for (index, child) in container.containedScenes.enumerated() {
                commands.append(
                    walk(
                        child, configuration: configuration, path: path + [index],
                        identity: container.identity(ofScene: index, under: identity)))
            }
            return commands
        }
        if let overlay = scene as? any OverlayScene {
            overlays.append(OverlayEntry(scene: overlay, configuration: configuration, identity: identity))
            return SceneCommands()
        }
        guard let configuring = scene as? any ConfiguringScene else { return SceneCommands() }
        var configuration = configuration
        configuring.configure(&configuration)
        guard let content = configuring.configuredContent else {
            // The end of a chain: the scene itself.
            guard let window = configuring as? any WindowScene else { return SceneCommands() }
            windows.append(WindowEntry(window: window, configuration: configuration, path: path, identity: identity))
            return SceneCommands.ofWindow
        }
        var commands = walk(content, configuration: configuration, path: path, identity: identity)
        if let modifier = configuring as? any SceneCommandsModifying {
            commands.modify(by: modifier.declaration, makeMenuBar: modifier.makeMenuBar)
        }
        return commands
    }
}

// MARK: - Which Scene Is Drawn

/// Which scene of the app a walk of its scene tree draws: at each container on
/// the way, the index of the scene that leads to it (``SceneContainer``).
///
/// Carried down the scene tree in the environment, as the walk passes through
/// modifiers that draw their content inside a view (`.onChange`), and taken off
/// before the scene's content draws.
struct SceneRenderTarget: Equatable {
    /// The indices still to follow, the next container's first.
    let path: [Int]
}

private struct SceneRenderTargetKey: EnvironmentKey {
    static let defaultValue: SceneRenderTarget? = nil
}

extension EnvironmentValues {
    /// Which of the app's scenes this walk of the scene tree draws, or `nil`
    /// outside a walk of an app's scenes.
    var sceneRenderTarget: SceneRenderTarget? {
        get { self[SceneRenderTargetKey.self] }
        set { self[SceneRenderTargetKey.self] = newValue }
    }
}

// MARK: - One Scene's Configuration

extension Scene {
    /// What the modifiers written on this scene configure for the frame of the
    /// window it opens at launch — its first window scene's.
    var sceneConfiguration: SceneConfiguration {
        SceneCatalog(self, identity: ViewIdentity(rootType: Self.self)).windows.first?.configuration
            ?? SceneConfiguration()
    }
}
