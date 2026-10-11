//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+PaletteOverride.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

// MARK: - Root Palette Discovery

/// Type-erased access to `EnvironmentModifier` internals.
///
/// This is intentionally limited to root modifier chain discovery.
@MainActor
private protocol AnyEnvironmentModifierNode {
    var anyEnvironmentKeyPath: AnyKeyPath { get }
    var anyEnvironmentValue: Any { get }
    var anyEnvironmentContent: Any { get }
}

@MainActor
extension EnvironmentModifier: AnyEnvironmentModifierNode {
    fileprivate var anyEnvironmentKeyPath: AnyKeyPath { keyPath }
    fileprivate var anyEnvironmentValue: Any { value }
    fileprivate var anyEnvironmentContent: Any { content }
}

/// The end of every scene's modifier chain.
///
/// A `.palette(...)` on the window group's root VIEW is honoured as if it had
/// been written on the scene, so the out-of-tree surfaces (status bar, app
/// header) are themed with the content. It is the statement closest to the
/// content, so it wins over a scene-level one.
@MainActor
extension WindowGroup: ConfiguringScene {
    func configure(_ configuration: inout SceneConfiguration) {
        if let palette = rootViewPalette { configuration.palette = palette }
    }

    var configuredContent: (any Scene)? { nil }

    /// The palette the outermost `.palette(...)` of the root view's modifier
    /// chain states, if any.
    private var rootViewPalette: (any Palette)? {
        var current: Any = content

        while let modifier = current as? any AnyEnvironmentModifierNode {
            // A key path equal to `\.palette` reads the palette, folded or not:
            // Tools/DedupCheck/manifest.json, `WindowGroup.(rootViewPalette`.
            // swiftlint:disable:next key_path_identity
            if modifier.anyEnvironmentKeyPath == \EnvironmentValues.palette,
                let palette = modifier.anyEnvironmentValue as? any Palette
            {
                return palette
            }
            current = modifier.anyEnvironmentContent
        }

        return nil
    }
}

// MARK: - Public Modifier

extension Scene {
    /// Sets the color palette for this scene — its content and every
    /// out-of-tree surface (app header, status bar).
    ///
    /// This is the scene-level counterpart to ``View/palette(_:)``: it lets the
    /// palette be written directly on a `WindowGroup`, matching SwiftUI's habit
    /// of theming at the scene level.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///         }
    ///         .palette(SystemPalette(.green))  // Classic green terminal
    ///     }
    /// }
    /// ```
    ///
    /// Applying `.palette(_:)` to the root *view* inside the `WindowGroup`
    /// remains equivalent and is honoured identically (see `WindowGroup`'s
    /// `ConfiguringScene` conformance).
    ///
    /// - Parameter palette: The palette to apply.
    /// - Returns: A scene that applies the palette.
    public func palette(_ palette: any Palette) -> some Scene {
        _PaletteScene(content: self, palette: palette)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that records a root ``Palette`` override on
/// its content. `RenderLoop` reads it from the ``SceneConfiguration`` and
/// installs it into the environment for the whole frame, so it reaches the
/// content view tree and the out-of-tree surfaces alike.
internal struct _PaletteScene<Content: Scene>: Scene {
    let content: Content
    let palette: any Palette

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_PaletteScene renders via SceneRenderable") }
}

extension _PaletteScene: ConfiguringScene {
    /// A palette closer to the content wins — one applied to an inner scene, or
    /// to the root view inside `WindowGroup` — mirroring how `.mouseSupport`
    /// composes and how SwiftUI environment modifiers resolve.
    func configure(_ configuration: inout SceneConfiguration) {
        configuration.palette = palette
    }

    var configuredContent: (any Scene)? { content }
}

extension _PaletteScene: SceneRenderable {
    /// The palette is applied by `RenderLoop`; rendering simply forwards to the
    /// wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}
