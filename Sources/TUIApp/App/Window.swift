//  🖥️ TUI — A Terminal UI framework for Swift
//  Window.swift
//
//  SwiftUI's `Window`: a scene that opens one window, by its identifier.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Window

/// A scene that presents its content in a single, unique window — mirrors
/// SwiftUI's `Window`.
///
/// ```swift
/// @main
/// struct Mail: App {
///     var body: some Scene {
///         WindowGroup { MailViewer() }
///         Window("Connection Doctor", id: "connection-doctor") {
///             ConnectionDoctor()
///         }
///     }
/// }
/// ```
///
/// ``EnvironmentValues/openWindow`` opens it by its identifier, over the
/// window in front, and opening it again while it is open brings it to the
/// front rather than opening a second. As the first scene of an app it is
/// the window opened at launch, as on macOS, where closing it then quits the
/// app.
///
/// A terminal shows one surface, so the window fills it, in front of the
/// windows already open, until it is dismissed or another is brought in front
/// of it (refusal review O9, ruled (b): secondary scenes are full-surface
/// covers stacked over the main one).
public struct Window<Content: View>: Scene {
    /// The window, drawn as a window group of one is: the same chrome, the same
    /// root palette, the same rendering.
    let group: WindowGroup<Content>

    /// Creates a window with a title and an identifier — mirrors SwiftUI's
    /// `init(_:id:content:)`.
    ///
    /// - Parameters:
    ///   - title: The ``Text`` title of the window.
    ///   - id: A unique string identifier that you can use to open the window.
    ///   - content: The view content to display in the window.
    public init(_ title: Text, id: String, @ViewBuilder content: () -> Content) {
        group = WindowGroup(title: title, id: id, content: content())
    }

    /// Creates a window with a localized title and an identifier — mirrors
    /// SwiftUI's `init(_:id:content:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the window.
    ///   - id: A unique string identifier that you can use to open the window.
    ///   - content: The view content to display in the window.
    public init(_ titleKey: LocalizedStringKey, id: String, @ViewBuilder content: () -> Content) {
        group = WindowGroup(title: Text(titleKey), id: id, content: content())
    }

    /// Creates a window with a title string and an identifier — mirrors
    /// SwiftUI's `init(_:id:content:)`, disfavoured so a string literal is a
    /// localized key.
    ///
    /// - Parameters:
    ///   - title: The title of the window, shown as written.
    ///   - id: A unique string identifier that you can use to open the window.
    ///   - content: The view content to display in the window.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, id: String, @ViewBuilder content: () -> Content) {
        group = WindowGroup(title: Text(title), id: id, content: content())
    }

    /// `Window` is a primitive scene: it renders through `SceneRenderable`, and
    /// this is never called.
    public var body: Never {
        fatalError("Window renders via SceneRenderable")
    }
}

// MARK: - Rendering and Configuration

extension Window: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        group.renderScene(context: context)
    }
}

/// The end of its chain, stating what the window group it is drawn as states:
/// a `.palette(...)` on its root view.
extension Window: ConfiguringScene {
    func configure(_ configuration: inout SceneConfiguration) {
        group.configure(&configuration)
    }

    var configuredContent: (any Scene)? { nil }
}

extension Window: WindowScene {
    var sceneID: String? { group.sceneID }

    var windowTitle: Text? { group.title }

    var opensOneWindow: Bool { true }

    var presentedValueType: Any.Type? { nil }
}

// MARK: - Window Scenes

/// A scene whose windows the run loop draws filling the terminal: a
/// ``WindowGroup`` or a ``Window``, at the end of its modifier chain. What the
/// scene presenter needs of it to open, list and close its windows.
@MainActor
protocol WindowScene: ConfiguringScene {
    /// The identifier ``EnvironmentValues/openWindow`` names it by, if it has
    /// one.
    var sceneID: String? { get }

    /// The title of its windows, if it has one.
    var windowTitle: Text? { get }

    /// Whether it opens one window at most — a `Window` — so that opening it
    /// again brings that window to the front.
    var opensOneWindow: Bool { get }

    /// The type of value its windows present — a `WindowGroup(for:)`'s — or
    /// `nil` for a scene whose windows present none.
    var presentedValueType: Any.Type? { get }
}
