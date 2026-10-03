//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+Environment.swift
//
//  SwiftUI's scene-level environment modifiers: a value, an observable object
//  or a transform written on a `WindowGroup` reaches everything the scene
//  draws — its content and the app header and status bar outside it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import TUIkitCore
import TUIkitView

// MARK: - Root Environment Discovery

/// A scene that writes into the frame's root environment.
///
/// `RenderLoop` applies it where it applies a scene's palette, so a value set
/// on a scene reaches the content tree and the out-of-tree surfaces alike —
/// a status bar item reading `@Environment(Model.self)` finds the model a
/// `WindowGroup { … }.environment(model)` put there.
@MainActor
internal protocol RootEnvironmentProvidingScene: Scene {
    /// Writes this scene's values, and those of the scenes inside it, into
    /// `environment`. Inner scenes write last, so the one closest to the
    /// content wins, as in a view's environment.
    func applyRootEnvironment(to environment: inout EnvironmentValues)
}

extension Scene {
    /// The root-environment writes of this scene's primitive, if it has any.
    func applyingRootEnvironment(to environment: inout EnvironmentValues) {
        (primitiveScene as? any RootEnvironmentProvidingScene)?.applyRootEnvironment(to: &environment)
    }
}

// MARK: - Public Modifiers

extension Scene {
    /// Sets the environment value of the specified key path to the given value
    /// for everything this scene draws — mirrors SwiftUI's
    /// `Scene.environment(_:_:)`.
    ///
    /// - Parameters:
    ///   - keyPath: A key path that indicates the property of the
    ///     ``EnvironmentValues`` structure to update.
    ///   - value: The new value to set for the item specified by `keyPath`.
    /// - Returns: A scene that has the given value set in its environment.
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some Scene {
        _EnvironmentScene(content: self) { $0[keyPath: keyPath] = value }
    }

    /// Places an observable object in the scene's environment — mirrors
    /// SwiftUI's `Scene.environment(_:)`.
    ///
    /// Descendants, the status bar's items among them, read it with
    /// `@Environment(MyModel.self)`. `nil` removes one placed further out.
    ///
    /// - Parameter object: The object to set for this object's type in the
    ///   environment, or `nil` to clear an object of this type.
    /// - Returns: A scene that has the given object set in its environment.
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some Scene {
        _EnvironmentScene(content: self) { $0[observable: T.self] = object }
    }

    /// Transforms the environment value of the specified key path with the
    /// given function — mirrors SwiftUI's `Scene.transformEnvironment(_:transform:)`.
    ///
    /// - Parameters:
    ///   - keyPath: The key path of the value to transform.
    ///   - transform: A function that changes the inherited value in place. It
    ///     runs once per frame, and so must be a pure function of the value.
    /// - Returns: A scene whose environment has the transformed value.
    public func transformEnvironment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) -> some Scene {
        _EnvironmentScene(content: self) { transform(&$0[keyPath: keyPath]) }
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that writes into the root environment.
/// `RenderLoop` reads it through ``RootEnvironmentProvidingScene``.
internal struct _EnvironmentScene<Content: Scene>: Scene {
    let content: Content
    let write: (inout EnvironmentValues) -> Void

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_EnvironmentScene renders via SceneRenderable") }
}

extension _EnvironmentScene: RootEnvironmentProvidingScene {
    func applyRootEnvironment(to environment: inout EnvironmentValues) {
        write(&environment)
        content.applyingRootEnvironment(to: &environment)
    }
}

extension _EnvironmentScene: SceneRenderable {
    /// The values are applied by `RenderLoop`; rendering forwards to the
    /// wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}

/// Pass-through for the four concerns this wrapper does not own, so it
/// composes with `.palette`, `.appearance`, `.mouseSupport` and `.chromeStyle`
/// in either order.
extension _EnvironmentScene: RootPaletteOverrideProvidingScene {
    func rootPaletteOverride() -> (any Palette)? {
        (content.primitiveScene as? any RootPaletteOverrideProvidingScene)?.rootPaletteOverride()
    }
}

extension _EnvironmentScene: RootAppearanceOverrideProvidingScene {
    func rootAppearanceOverride() -> Appearance? {
        (content.primitiveScene as? any RootAppearanceOverrideProvidingScene)?.rootAppearanceOverride()
    }
}

extension _EnvironmentScene: MouseSupportProvidingScene {
    func resolvedMouseSupport() -> MouseSupport? {
        (content.primitiveScene as? any MouseSupportProvidingScene)?.resolvedMouseSupport()
    }
}

extension _EnvironmentScene: RootChromeStyleProvidingScene {
    func rootChromeStyle() -> (appHeader: ChromeStyle?, statusBar: ChromeStyle?) {
        (content.primitiveScene as? any RootChromeStyleProvidingScene)?.rootChromeStyle() ?? (nil, nil)
    }
}

// MARK: - Forwarding Through the Other Wrappers

/// Each of the other scene wrappers passes the environment through, so
/// `.environment(model)` composes with them in either order.
extension _PaletteScene: RootEnvironmentProvidingScene {
    func applyRootEnvironment(to environment: inout EnvironmentValues) {
        content.applyingRootEnvironment(to: &environment)
    }
}

extension _AppearanceScene: RootEnvironmentProvidingScene {
    func applyRootEnvironment(to environment: inout EnvironmentValues) {
        content.applyingRootEnvironment(to: &environment)
    }
}

extension _MouseSupportScene: RootEnvironmentProvidingScene {
    func applyRootEnvironment(to environment: inout EnvironmentValues) {
        content.applyingRootEnvironment(to: &environment)
    }
}

extension _ChromeStyleScene: RootEnvironmentProvidingScene {
    func applyRootEnvironment(to environment: inout EnvironmentValues) {
        content.applyingRootEnvironment(to: &environment)
    }
}
