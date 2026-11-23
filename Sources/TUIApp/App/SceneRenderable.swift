//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneRenderable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Scene Rendering Protocol

/// Bridge from the `Scene` hierarchy to the `View` rendering system.
///
/// `SceneRenderable` sits outside the `View`/`Renderable` dual system.
/// It connects the `App.body` (which produces a `Scene`) to the view
/// tree rendering via ``renderToBuffer(_:context:)``.
///
/// `RenderLoop` renders the scene returned by `App.body` through
/// ``Scene/renderSceneTree(context:)``, which walks that scene's `body`
/// chain to the first conformer of this protocol — so a custom scene is
/// rendered by whichever primitive it is made of. The primitive (typically
/// ``WindowGroup``) then invokes the free function `renderToBuffer` on its
/// content view, entering the standard `Renderable`-or-`body` dispatch.
///
/// This protocol stays `internal` on purpose: it is the scene-side twin of
/// `Renderable`, but where a `View` outside the framework has a legitimate
/// reason to draw itself into a buffer, a scene does not — a terminal app has
/// exactly one window, and what a custom scene has to say is said by the
/// `WindowGroup` (and the scene modifiers) its `body` returns.
@MainActor
internal protocol SceneRenderable {
    /// Renders the scene's content into a ``FrameBuffer``.
    ///
    /// The caller (`RenderLoop`) is responsible for writing the buffer
    /// to the terminal via `FrameDiffWriter`.
    ///
    /// - Parameter context: The rendering context with layout constraints.
    /// - Returns: The rendered frame buffer.
    func renderScene(context: RenderContext) -> FrameBuffer
}
