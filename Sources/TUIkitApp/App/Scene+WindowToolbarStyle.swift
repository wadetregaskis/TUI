//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+WindowToolbarStyle.swift
//
//  SwiftUI's window toolbar styles: the one style every bar of the window
//  frames itself in.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Window Toolbar Style

/// A specification for the appearance and behavior of a window's toolbar —
/// mirrors SwiftUI's `WindowToolbarStyle`.
///
/// In a terminal the style is how EVERY bar of the window — the top bar and
/// the bottom bar, the line of key hints included — separates itself from the
/// page, one style for all of them, set on the scene:
///
/// | Style | The bars |
/// |---|---|
/// | ``WindowToolbarStyle/automatic``, ``WindowToolbarStyle/expanded`` | boxed, like a container view (``ChromeStyle/bordered``) |
/// | ``WindowToolbarStyle/unified`` | a full-width rule on the page's side (``ChromeStyle/rule``) |
/// | ``WindowToolbarStyle/unifiedCompact`` | the items alone, on the bars' background (``ChromeStyle/compact``) |
///
/// The `showsTitle:` forms say whether the top bar's title slot shows the
/// window's `.navigationTitle`.
///
/// A style of your own conforms to nothing a terminal can draw, and is read as
/// ``WindowToolbarStyle/automatic``.
public protocol WindowToolbarStyle {}

/// How the framework reads one of its own styles.
protocol _ResolvingWindowToolbarStyle {
    /// The frame every bar draws.
    var chrome: ChromeStyle { get }
    /// Whether the top bar's title slot shows the window's title.
    var showsTitle: Bool { get }
}

/// The default window toolbar style — mirrors SwiftUI's
/// `DefaultWindowToolbarStyle`: the bars boxed.
public struct DefaultWindowToolbarStyle: WindowToolbarStyle, _ResolvingWindowToolbarStyle {
    var chrome: ChromeStyle { .bordered }
    var showsTitle: Bool { true }

    /// Creates a default window toolbar style.
    public init() {}
}

/// A window toolbar style which displays its title bar area above the
/// toolbar — mirrors SwiftUI's `ExpandedWindowToolbarStyle`: the bars boxed.
public struct ExpandedWindowToolbarStyle: WindowToolbarStyle, _ResolvingWindowToolbarStyle {
    var chrome: ChromeStyle { .bordered }
    var showsTitle: Bool { true }

    /// Creates an expanded window toolbar style.
    public init() {}
}

/// A window toolbar style which displays its title bar area inline with the
/// toolbar — mirrors SwiftUI's `UnifiedWindowToolbarStyle`: each bar ruled on
/// the page's side.
public struct UnifiedWindowToolbarStyle: WindowToolbarStyle, _ResolvingWindowToolbarStyle {
    var chrome: ChromeStyle { .rule }
    let showsTitle: Bool

    /// Creates a unified window toolbar style.
    public init() {
        self.showsTitle = true
    }

    /// Creates a unified window toolbar style.
    ///
    /// - Parameter showsTitle: Whether the top bar's title slot shows the
    ///   window's title.
    public init(showsTitle: Bool) {
        self.showsTitle = showsTitle
    }
}

/// A window toolbar style similar to ``UnifiedWindowToolbarStyle``, but with a
/// more compact vertical size — mirrors SwiftUI's
/// `UnifiedCompactWindowToolbarStyle`: the bars' items alone, with no rule and
/// no box.
public struct UnifiedCompactWindowToolbarStyle: WindowToolbarStyle, _ResolvingWindowToolbarStyle {
    var chrome: ChromeStyle { .compact }
    let showsTitle: Bool

    /// Creates a unified compact window toolbar style.
    public init() {
        self.showsTitle = true
    }

    /// Creates a unified compact window toolbar style.
    ///
    /// - Parameter showsTitle: Whether the top bar's title slot shows the
    ///   window's title.
    public init(showsTitle: Bool) {
        self.showsTitle = showsTitle
    }
}

extension WindowToolbarStyle where Self == DefaultWindowToolbarStyle {
    /// The default window toolbar style: the bars boxed.
    public static var automatic: DefaultWindowToolbarStyle { DefaultWindowToolbarStyle() }
}

extension WindowToolbarStyle where Self == ExpandedWindowToolbarStyle {
    /// A window toolbar style which displays its title bar area above the
    /// toolbar: the bars boxed.
    public static var expanded: ExpandedWindowToolbarStyle { ExpandedWindowToolbarStyle() }
}

extension WindowToolbarStyle where Self == UnifiedWindowToolbarStyle {
    /// A window toolbar style which displays its title bar area inline with the
    /// toolbar: each bar ruled on the page's side.
    public static var unified: UnifiedWindowToolbarStyle { UnifiedWindowToolbarStyle() }

    /// A window toolbar style which displays its title bar area inline with the
    /// toolbar, the title shown or not.
    ///
    /// - Parameter showsTitle: Whether the top bar's title slot shows the
    ///   window's title.
    public static func unified(showsTitle: Bool) -> UnifiedWindowToolbarStyle {
        UnifiedWindowToolbarStyle(showsTitle: showsTitle)
    }
}

extension WindowToolbarStyle where Self == UnifiedCompactWindowToolbarStyle {
    /// A window toolbar style with a more compact vertical size: the bars'
    /// items alone.
    public static var unifiedCompact: UnifiedCompactWindowToolbarStyle { UnifiedCompactWindowToolbarStyle() }

    /// A window toolbar style with a more compact vertical size, the title
    /// shown or not.
    ///
    /// - Parameter showsTitle: Whether the top bar's title slot shows the
    ///   window's title.
    public static func unifiedCompact(showsTitle: Bool) -> UnifiedCompactWindowToolbarStyle {
        UnifiedCompactWindowToolbarStyle(showsTitle: showsTitle)
    }
}

// MARK: - Public Modifiers

extension Scene {
    /// Sets the style for the toolbar defined within this scene — mirrors
    /// SwiftUI's `Scene.windowToolbarStyle(_:)`.
    ///
    /// One style for every bar of the window, the top bar and the bottom bar
    /// alike: a boxed footer under a ruled header reads as a mistake.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .windowToolbarStyle(.unifiedCompact)
    /// ```
    ///
    /// - Parameter style: The style to apply to the toolbar.
    public func windowToolbarStyle<S: WindowToolbarStyle>(_ style: S) -> some Scene {
        _WindowToolbarStyleScene(content: self, style: style)
    }

    /// Sets the style for the toolbar defined within this scene, from a style
    /// chosen at run time.
    ///
    /// A TUIkit addition beside SwiftUI's generic form: a scene's modifiers
    /// cannot be chosen with an `if`, so an app that lets its user pick the
    /// style — the Example's Theme page — hands the choice over erased.
    ///
    /// - Parameter style: The style to apply to the toolbar.
    @_disfavoredOverload
    public func windowToolbarStyle(_ style: any WindowToolbarStyle) -> some Scene {
        _WindowToolbarStyleScene(content: self, style: style)
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper recording the window toolbar style.
///
/// The bars' style decides how many rows they take, and the page's height is
/// whatever is left, so `RenderLoop` reads it from the ``SceneConfiguration``
/// at the top of the frame, before anything is laid out.
internal struct _WindowToolbarStyleScene<Content: Scene>: Scene {
    let content: Content
    let style: any WindowToolbarStyle

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_WindowToolbarStyleScene renders via SceneRenderable") }
}

extension _WindowToolbarStyleScene: ConfiguringScene {
    /// Innermost wins, as for every scene modifier: this writes over what the
    /// scenes outside it wrote.
    func configure(_ configuration: inout SceneConfiguration) {
        let resolving = style as? any _ResolvingWindowToolbarStyle ?? DefaultWindowToolbarStyle()
        configuration.toolbarStyle = resolving.chrome
        configuration.showsTitle = resolving.showsTitle
    }

    var configuredContent: (any Scene)? { content }
}

extension _WindowToolbarStyleScene: SceneRenderable {
    /// The style is applied by `RenderLoop` before the frame is laid out;
    /// rendering forwards to the wrapped scene.
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}
