//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+OnChange.swift
//
//  SwiftUI's scene-level `onChange(of:initial:_:)`: an action run when a value
//  the scene was built with changes between frames.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

extension Scene {
    /// Adds an action to perform when the given value changes — mirrors
    /// SwiftUI's `Scene.onChange(of:initial:_:)`.
    ///
    /// The value is the scene's, not a window's: it is compared once a frame,
    /// before the windows draw, and the action runs once when it changed —
    /// however many of the scene's windows are open, none included — with the
    /// old and new values. With `initial`, it also runs on the app's first
    /// frame, when the scene first appears, and not again as windows open.
    ///
    /// - Parameters:
    ///   - value: The value to check against when determining whether to run
    ///     the closure.
    ///   - initial: Whether the action should be run when the scene first
    ///     renders.
    ///   - action: A closure to run when the value changes.
    /// - Returns: A scene that triggers an action in response to a change.
    public func onChange<V: Equatable>(
        of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void
    ) -> some Scene {
        _OnChangeScene(content: self, value: value, initial: initial, action: action)
    }

    /// Adds an action to perform when the given value changes, without its old
    /// and new values — mirrors SwiftUI's `Scene.onChange(of:initial:_:)`.
    ///
    /// Compared once a frame for the scene, as the form above is.
    ///
    /// - Parameters:
    ///   - value: The value to check against when determining whether to run
    ///     the closure.
    ///   - initial: Whether the action should be run when the scene first
    ///     renders.
    ///   - action: A closure to run when the value changes.
    /// - Returns: A scene that triggers an action in response to a change.
    public func onChange<V: Equatable>(
        of value: V, initial: Bool = false, _ action: @escaping () -> Void
    ) -> some Scene {
        _OnChangeScene(content: self, value: value, initial: initial) { _, _ in action() }
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that watches a value for its scene.
///
/// Not inside a window's walk: the scene catalogue gathers it each frame
/// (``SceneCatalog/watches``), and the run loop compares its value once,
/// before any window draws (`RenderLoop.adoptScenes`). Compared as each window
/// drew, keyed by the window's identity, it ran its action once for every
/// open window, and again with `initial` for every window opened.
internal struct _OnChangeScene<Content: Scene, V: Equatable>: Scene {
    let content: Content
    let value: V
    let initial: Bool
    let action: (V, V) -> Void

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_OnChangeScene renders via SceneRenderable") }
}

/// Draws its content: the watching is the scene's, done before the windows
/// draw.
extension _OnChangeScene: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}

/// States nothing of its own: the watching happens before the windows draw.
/// It is a link in the chain all the same, so the modifiers on either side of
/// it are found.
extension _OnChangeScene: ConfiguringScene {
    func configure(_ configuration: inout SceneConfiguration) {}

    var configuredContent: (any Scene)? { content }
}

extension _OnChangeScene: WatchingScene {
    func compare(in storage: StateStorage, at key: StateStorage.StateKey) {
        storage.compareTrackedValue(value, at: key, initial: initial, action: action)
    }
}

// MARK: - Watching Scenes

/// A scene modifier that watches a value for its scene: `onChange(of:)`.
@MainActor
protocol WatchingScene: ConfiguringScene {
    /// Compares its value with the one `storage` tracks under `key`, runs its
    /// action where the value changed, and tracks the value.
    func compare(in storage: StateStorage, at key: StateStorage.StateKey)
}

/// One scene's watch, as the scene catalogue gathered it this frame.
struct SceneWatch {
    /// The modifier that watches.
    let scene: any WatchingScene

    /// Where its last value is kept: at its scene's ``place(under:)``, by its
    /// place in the scene's chain of watches.
    let key: StateStorage.StateKey

    /// The `index`th watch, from the outside in, of the scene whose watches
    /// are kept at `place`.
    init(_ scene: any WatchingScene, at place: ViewIdentity, index: Int) {
        self.scene = scene
        key = StateStorage.StateKey(identity: place, propertyIndex: index)
    }

    /// Where the watches of the scene drawn at `identity` keep their values:
    /// below its place in the body, at an identity no view is drawn at — so no
    /// window's walk, nor any `onChange` in one, claims it.
    static func place(under identity: ViewIdentity) -> ViewIdentity {
        identity.child(erasedType: Self.self, key: "onChange")
    }
}

extension SceneCatalog {
    /// Compares every scene's watched value once — what a scene's
    /// `onChange(of:)` does each frame — keeping what each tracks through the
    /// end of the pass.
    func compareWatches(in storage: StateStorage) {
        for watch in watches {
            storage.markActive(watch.key.identity)
            watch.scene.compare(in: storage, at: watch.key)
        }
    }
}
