//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneBuilder+Composition.swift
//
//  Several scenes in one body: the builder's block of any length, a scene
//  behind `if #available`, and `Group` of scenes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Builder's Composition

extension SceneBuilder {
    /// Builds a scene from several written one after another — mirrors
    /// SwiftUI's variadic `buildBlock(_:)`.
    ///
    /// Each is a scene of the app: the first window scene opens at launch, and
    /// the others are opened by ``EnvironmentValues/openWindow``,
    /// ``EnvironmentValues/openSettings`` or their own presentation binding.
    ///
    /// - Parameter content: The scenes, in declaration order.
    /// - Returns: A scene made of them.
    public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> some Scene {
        _TupleScene(repeat each content)
    }

    /// Builds a scene that exists only where an availability check passed —
    /// mirrors SwiftUI's `buildOptional(_:)`.
    ///
    /// SwiftUI's builder takes only an availability-checked scene here, so an
    /// `if` on a value does not compile around a scene, and an
    /// `if #available` does; the parameter's type is what says so.
    ///
    /// - Parameter scene: The scene, or `nil` where the check failed.
    /// - Returns: The scene, or none.
    public static func buildOptional(_ scene: (any Scene & _LimitedAvailabilitySceneMarker)?) -> some Scene {
        _OptionalScene(scene: scene)
    }

    /// Builds a scene inside an `if #available` — mirrors SwiftUI's
    /// `buildLimitedAvailability(_:)`, erasing a type the check may make
    /// unavailable.
    ///
    /// - Parameter scene: The scene inside the check.
    /// - Returns: The scene, erased.
    public static func buildLimitedAvailability(_ scene: some Scene) -> any Scene & _LimitedAvailabilitySceneMarker {
        _LimitedAvailabilityScene(scene: scene)
    }
}

/// What ``SceneBuilder/buildLimitedAvailability(_:)`` returns and
/// ``SceneBuilder/buildOptional(_:)`` takes: a scene inside an availability
/// check. SwiftUI's own marker, under its name; you don't use it directly.
@MainActor
public protocol _LimitedAvailabilitySceneMarker {}

// MARK: - Several Scenes

/// The scenes of one builder block, in declaration order: each its own child
/// of the block's identity, by position, as a `TupleView`'s views are.
struct _TupleScene<each Content: Scene>: Scene {
    let content: (repeat each Content)

    init(_ content: repeat each Content) {
        self.content = (repeat each content)
    }

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_TupleScene renders via SceneRenderable") }
}

extension _TupleScene: SceneContainer {
    var containedScenes: [any Scene] {
        var scenes: [any Scene] = []
        for scene in repeat each content { scenes.append(scene) }
        return scenes
    }

    var givesChildrenIdentities: Bool { true }
}

/// A scene behind an `if #available` with no `else`: the scene where the check
/// passed, nothing where it failed.
struct _OptionalScene: Scene {
    let scene: (any Scene & _LimitedAvailabilitySceneMarker)?

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_OptionalScene renders via SceneRenderable") }
}

extension _OptionalScene: SceneContainer {
    var containedScenes: [any Scene] { scene.map { [$0] } ?? [] }

    var givesChildrenIdentities: Bool { false }
}

/// A scene inside an `if #available`, its type erased.
struct _LimitedAvailabilityScene: Scene, _LimitedAvailabilitySceneMarker {
    let scene: any Scene

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_LimitedAvailabilityScene renders via SceneRenderable") }
}

extension _LimitedAvailabilityScene: SceneContainer {
    var containedScenes: [any Scene] { [scene] }

    var givesChildrenIdentities: Bool { false }
}

// MARK: - Group

extension Group: Scene where Content: Scene {
    /// Creates a group of scenes — mirrors SwiftUI's `Group.init(content:)`
    /// for scenes: to apply a modifier to several at once, or to write
    /// several where one is expected.
    ///
    /// - Parameter content: A ``SceneBuilder`` that creates the scenes.
    public init(@SceneBuilder content: () -> Content) {
        self = .grouping(content())
    }

    /// A group is a container: it renders through `SceneRenderable`, and this
    /// is never called.
    public var body: Never { fatalError("Group renders its scenes via SceneRenderable") }
}

extension Group: SceneContainer where Content: Scene {
    var containedScenes: [any Scene] { [content] }

    var givesChildrenIdentities: Bool { false }
}

// MARK: - Containers

/// A scene made of other scenes, which states nothing of its own: a builder's
/// block, an optional or availability-checked scene, a `Group`.
///
/// The scene catalog walks into each (``SceneCatalog``), and the run loop
/// renders the one of its scenes it is drawing (``SceneRenderTarget``).
@MainActor
protocol SceneContainer: Scene {
    /// The scenes it holds, in declaration order.
    var containedScenes: [any Scene] { get }

    /// Whether each of them is drawn at a child identity of its own, by
    /// position — a block's scenes are — or at the container's.
    var givesChildrenIdentities: Bool { get }
}

extension SceneContainer {
    /// The identity scene `index` is drawn at, under `identity`.
    func identity(ofScene index: Int, under identity: ViewIdentity) -> ViewIdentity {
        guard givesChildrenIdentities else { return identity }
        return identity.child(erasedType: type(of: containedScenes[index]), index: index)
    }

    /// Draws the scene the frame's target names, at its identity: the next
    /// step of the target's path.
    ///
    /// With no target — a scene drawn outside an app's run loop — the first
    /// window scene among its scenes, the one an app would open at launch.
    func renderTargetedScene(context: RenderContext) -> FrameBuffer {
        let target = context.environment.sceneRenderTarget ?? SceneCatalog(self, identity: context.identity).launchTarget
        guard let target, let index = target.path.first, containedScenes.indices.contains(index) else {
            return FrameBuffer()
        }
        var inner = context
        inner.identity = identity(ofScene: index, under: context.identity)
        inner.environment.sceneRenderTarget = SceneRenderTarget(path: Array(target.path.dropFirst()))
        return containedScenes[index].renderSceneTree(context: inner)
    }
}

extension _TupleScene: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer { renderTargetedScene(context: context) }
}

extension _OptionalScene: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer { renderTargetedScene(context: context) }
}

extension _LimitedAvailabilityScene: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer { renderTargetedScene(context: context) }
}

extension Group: SceneRenderable where Content: Scene {
    func renderScene(context: RenderContext) -> FrameBuffer { renderTargetedScene(context: context) }
}
