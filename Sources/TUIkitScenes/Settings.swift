//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Settings.swift
//
//  SwiftUI's `Settings` scene: the app's settings, presented as a sheet over
//  the window in front by `openSettings`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitApp
import TUIkitFoundation
import TUIkitPresentation

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
/// ``EnvironmentValues/openSettings`` and a ``SettingsLink`` present it as a
/// sheet over the window in front (refusal review O9, ruled (b)), sized to its content as every sheet is; Escape, or
/// `dismiss()` inside it, closes it. On macOS it is a window of its own, which
/// a terminal cannot open beside another. Its modifiers — `.environment`, a
/// palette — reach its content alone.
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

    /// An empty view presenting the content as a sheet while the presenter
    /// says the settings are up; dismissing the sheet tells it they are not.
    package func overlay(in presenter: ScenePresenter) -> AnyView {
        let isPresented = Binding(
            get: { presenter.isPresentingSettings },
            set: { presenter.isPresentingSettings = $0 })
        return AnyView(EmptyView().sheet(isPresented: isPresented) { content })
    }
}
