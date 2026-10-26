//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+MouseSupport.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Public Modifier

extension Scene {
    /// Configures which kinds of mouse interactions the app will
    /// receive from the terminal.
    ///
    /// See ``MouseSupport`` for details on each feature and the
    /// trade-off with native terminal text selection.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///         }
    ///         .mouseSupport(.full)  // enable hover effects too
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter support: The desired mouse support configuration.
    /// - Returns: A scene that applies the configuration.
    public func mouseSupport(_ support: MouseSupport) -> some Scene {
        _MouseSupportScene(content: self, support: support)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that records a ``MouseSupport``
/// configuration on its content. `RenderLoop` reads it from the
/// ``SceneConfiguration`` to decide which terminal tracking mode to apply each
/// frame.
internal struct _MouseSupportScene<Content: Scene>: Scene {
    let content: Content
    let support: MouseSupport

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_MouseSupportScene renders via SceneRenderable") }
}

extension _MouseSupportScene: ConfiguringScene {
    /// Inner `.mouseSupport` calls shadow outer ones — the closest (innermost)
    /// modifier to the content wins, mirroring how SwiftUI environment-style
    /// modifiers compose. A wrapper that states nothing about the mouse (a
    /// `.palette(...)`) shadows nothing.
    func configure(_ configuration: inout SceneConfiguration) {
        configuration.mouseSupport = support
    }

    var configuredContent: (any Scene)? { content }
}

// MARK: - SceneRenderable forwarding

extension _MouseSupportScene: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        // Forward rendering to the wrapped content. The mouse support
        // configuration is metadata the run loop reads from the scene's
        // configuration — it doesn't affect what gets drawn.
        content.renderSceneTree(context: context)
    }
}
