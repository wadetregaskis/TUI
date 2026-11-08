//  🖥️ TUI — A Terminal UI framework for Swift
//  Settings.swift
//
//  SwiftUI's `Settings` scene: the app's settings, the settings panel's first
//  tabs, which F2, `openSettings` and Settings… present over the window in
//  front.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
import TUIFoundation

/// A scene that presents an interface for viewing and modifying an app's
/// settings — mirrors SwiftUI's `Settings`.
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///         Settings {
///             SettingsView()
///         }
///     }
/// }
/// ```
///
/// The content is the first tabs of the settings panel every TUI app has: a
/// `TabView`'s tabs become one tab each, in order, and any other content one
/// tab named after the app. TUI's own tabs, View and Accessibility, follow
/// after a divider (`builtInSettingsTab(_:visibility:)` hides or replaces
/// them). F2, ``EnvironmentValues/openSettings``, a ``SettingsLink``, the menu
/// bar's Settings… and its key — ⌘, through `commandKey`, or the one the
/// scene's `.keyboardShortcut` states — present the panel as a sheet over the
/// window in front (refusal review O9, ruled (b); the owner's panel,
/// 2026-11-08); Escape, F2, Done, or `dismiss()` inside it, closes it. On
/// macOS it is a window of its own, which a terminal cannot open beside
/// another. Its modifiers — `.environment`, a palette — reach its content
/// alone.
public struct Settings<Content: View>: Scene {
    /// The settings' content.
    let content: Content

    /// Creates a scene that presents an interface for viewing and modifying an
    /// app's preferences — mirrors SwiftUI's `init(content:)`.
    ///
    /// - Parameter content: A view that represents the content of the scene.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// `Settings` is presented over the window in front by the app's scene
    /// presenter: this is never called.
    public var body: Never {
        fatalError("Settings is presented by the scene presenter")
    }
}

extension Settings: OverlayScene {
    package var isSettings: Bool { true }

    /// The settings panel's first tabs: a `TabView`'s tabs, one each, or the
    /// content as one tab, named after the app.
    package var settingsTabs: [SettingsTab] {
        (content as? any SettingsTabsProviding)?.settingsTabs ?? [SettingsTab(title: nil, content: AnyView(content))]
    }

    /// Never asked: the settings panel draws the scene's tabs.
    package func overlay(in presenter: ScenePresenter) -> AnyView {
        AnyView(EmptyView())
    }
}
