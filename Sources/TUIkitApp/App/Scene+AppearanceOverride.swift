//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+AppearanceOverride.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Public Modifier

extension Scene {
    /// Sets the ``Appearance`` (border style) for this scene — its content and
    /// every out-of-tree surface (app header, status bar) alike.
    ///
    /// This is the scene-level counterpart to ``View/appearance(_:)``: a
    /// `View`-level `.appearance(...)` only reaches the content subtree, whereas
    /// the app header and status bar are rendered outside the view tree by the
    /// framework and otherwise follow the appearance manager (F2/F3/the
    /// appearance picker). Applying the appearance here routes it to all three.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     @State private var border: BorderStyle?
    ///     var body: some Scene {
    ///         WindowGroup { ContentView(border: $border) }
    ///             // A custom border overrides the built-in appearance app-wide;
    ///             // `nil` defers to F2/F3/the appearance picker.
    ///             .appearance(border.map {
    ///                 Appearance(id: Appearance.ID(rawValue: "custom"), borderStyle: $0)
    ///             })
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter appearance: The appearance to apply app-wide, or `nil` to
    ///   leave the appearance manager (F2/F3/the appearance picker) in charge.
    /// - Returns: A scene that applies the appearance.
    public func appearance(_ appearance: Appearance?) -> some Scene {
        _AppearanceScene(content: self, appearance: appearance)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that records a root ``Appearance`` override
/// on its content.
///
/// `RenderLoop` reads it from the ``SceneConfiguration`` and installs it into
/// the environment for the whole frame, so it reaches the content view tree and
/// the out-of-tree surfaces alike. Without that, a scene-level appearance would
/// only reach the content: `RenderLoop` derives the frame appearance from the
/// appearance manager (F2/F3/the appearance picker), which the header and status
/// bar read but the content's own `.appearance(...)` modifier cannot reach.
internal struct _AppearanceScene<Content: Scene>: Scene {
    let content: Content
    let appearance: Appearance?

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_AppearanceScene renders via SceneRenderable") }
}

extension _AppearanceScene: ConfiguringScene {
    /// An appearance closer to the content wins — one applied to an inner scene —
    /// mirroring how `.palette(...)` composes and how SwiftUI environment
    /// modifiers resolve. A `nil` here means "no opinion", so it leaves an outer
    /// `.appearance(...)` showing through.
    func configure(_ configuration: inout SceneConfiguration) {
        if let appearance { configuration.appearance = appearance }
    }

    var configuredContent: (any Scene)? { content }
}

extension _AppearanceScene: SceneRenderable {
    /// The appearance is applied by `RenderLoop`; rendering simply forwards to
    /// the wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}
