//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+ChromeStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Public Modifiers

extension Scene {
    /// Sets how BOTH framing bars — the app header and the status bar — separate
    /// themselves from the page.
    ///
    /// The one-line spelling, and the one to reach for: a boxed footer under a
    /// ruled header reads as a mistake, so the styles want to move together
    /// unless a mismatch is deliberate.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .chromeStyle(.bordered)
    /// ```
    ///
    /// - Parameter style: The style both bars adopt.
    public func chromeStyle(_ style: ChromeStyle) -> some Scene {
        _ChromeStyleScene(content: self, appHeaderStyle: style, statusBarStyle: style)
    }

    /// Sets the two framing bars' styles independently.
    ///
    /// The deliberate-mismatch spelling — a compact header over a bordered
    /// status bar, say, when the page's own top edge is chrome enough.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .chromeStyle(appHeader: .compact, statusBar: .bordered)
    /// ```
    ///
    /// - Parameters:
    ///   - appHeader: The app header's style.
    ///   - statusBar: The status bar's style.
    public func chromeStyle(appHeader: ChromeStyle, statusBar: ChromeStyle) -> some Scene {
        _ChromeStyleScene(content: self, appHeaderStyle: appHeader, statusBarStyle: statusBar)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper recording the chrome styles for the frame.
///
/// Both bars are rendered OUTSIDE the view tree by `RenderLoop`, and — unlike
/// the appearance, which only has to reach the render — their style also
/// decides how many rows the page has to give up. `RenderLoop` therefore reads
/// it from the ``SceneConfiguration`` at the top of the frame, before it
/// reserves anything.
internal struct _ChromeStyleScene<Content: Scene>: Scene {
    let content: Content
    let appHeaderStyle: ChromeStyle?
    let statusBarStyle: ChromeStyle?

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_ChromeStyleScene renders via SceneRenderable") }
}

extension _ChromeStyleScene: ConfiguringScene {
    /// Per bar and independently, so an inner `.chromeStyle(appHeader:statusBar:)`
    /// overriding only one of them still lets an outer blanket
    /// `.chromeStyle(_:)` cover the other. Innermost wins, as for every scene
    /// modifier: this writes over what the scenes outside it wrote.
    func configure(_ configuration: inout SceneConfiguration) {
        if let appHeaderStyle { configuration.topBarStyle = appHeaderStyle }
        if let statusBarStyle { configuration.bottomBarStyle = statusBarStyle }
    }

    var configuredContent: (any Scene)? { content }
}

extension _ChromeStyleScene: SceneRenderable {
    /// The styles are applied by `RenderLoop` before the frame is laid out;
    /// rendering forwards to the wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}
