//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+OnChange.swift
//
//  SwiftUI's scene-level `onChange(of:initial:_:)`: an action run when a value
//  the scene was built with changes between frames.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension Scene {
    /// Adds an action to perform when the given value changes — mirrors
    /// SwiftUI's `Scene.onChange(of:initial:_:)`.
    ///
    /// The value is compared each frame, as the view modifier of the same
    /// name compares it, and the action runs after the frame that saw it
    /// change, with the old and new values.
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

/// Framework-internal scene wrapper that watches a value. It draws its content
/// inside the view modifier that does the watching, so the comparison, the
/// once-per-frame guard and the timing of the action are that modifier's.
internal struct _OnChangeScene<Content: Scene, V: Equatable>: Scene {
    let content: Content
    let value: V
    let initial: Bool
    let action: (V, V) -> Void

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_OnChangeScene renders via SceneRenderable") }
}

/// A scene drawn as a view, so a view modifier can wrap it.
private struct _SceneContentView<Content: Scene>: View, Renderable {
    let scene: Content

    var body: Never { fatalError("_SceneContentView renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        scene.renderSceneTree(context: context)
    }
}

extension _OnChangeScene: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        TUIkitView.renderToBuffer(
            OnChangeModifier(
                content: _SceneContentView(scene: content), value: value, initial: initial,
                action: action),
            context: context)
    }
}

/// Pass-through for the concerns this wrapper does not own, so it composes
/// with the other scene modifiers in either order.
extension _OnChangeScene: RootEnvironmentProvidingScene {
    func applyRootEnvironment(to environment: inout EnvironmentValues) {
        content.applyingRootEnvironment(to: &environment)
    }
}

extension _OnChangeScene: RootPaletteOverrideProvidingScene {
    func rootPaletteOverride() -> (any Palette)? {
        (content.primitiveScene as? any RootPaletteOverrideProvidingScene)?.rootPaletteOverride()
    }
}

extension _OnChangeScene: RootAppearanceOverrideProvidingScene {
    func rootAppearanceOverride() -> Appearance? {
        (content.primitiveScene as? any RootAppearanceOverrideProvidingScene)?.rootAppearanceOverride()
    }
}

extension _OnChangeScene: MouseSupportProvidingScene {
    func resolvedMouseSupport() -> MouseSupport? {
        (content.primitiveScene as? any MouseSupportProvidingScene)?.resolvedMouseSupport()
    }
}

extension _OnChangeScene: RootChromeStyleProvidingScene {
    func rootChromeStyle() -> (appHeader: ChromeStyle?, statusBar: ChromeStyle?) {
        (content.primitiveScene as? any RootChromeStyleProvidingScene)?.rootChromeStyle() ?? (nil, nil)
    }
}
