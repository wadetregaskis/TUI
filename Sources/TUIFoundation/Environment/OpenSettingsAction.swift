//  🖥️ TUI — A Terminal UI framework for Swift
//  OpenSettingsAction.swift
//
//  SwiftUI's `\.openSettings`: presents the app's `Settings` scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// An action that presents the settings scene for an app — mirrors SwiftUI's
/// `OpenSettingsAction`.
///
/// Read it from the environment and call it:
///
/// ```swift
/// struct AdvancedSettingsButton: View {
///     @AppStorage("selectedSettingsTab") private var selectedSettingsTab = SettingsTab.general
///     @Environment(\.openSettings) private var openSettings
///
///     var body: some View {
///         Button("Open Advanced Settings…") {
///             selectedSettingsTab = .advanced
///             openSettings()
///         }
///     }
/// }
/// ```
///
/// The app's `Settings` scene is presented as a sheet over the window in
/// front (refusal review O9, ruled (b)); where it is up already, this does
/// nothing more. An app that declares no `Settings` scene presents nothing.
///
/// Equal to another when both reach the same app: the memos below a view that
/// reads it stay on.
public struct OpenSettingsAction: Sendable, Equatable {
    /// Where the action goes, or `nil` outside a running app.
    private let handler: SceneActionHandler?

    /// The action that hands its calls to `handler`.
    package init(handler: SceneActionHandler?) {
        self.handler = handler
    }

    /// Opens the window associated to the `Settings` scene defined by this
    /// app, if one exists — mirrors SwiftUI's `callAsFunction()`: here, its
    /// sheet, over the window in front.
    @MainActor
    public func callAsFunction() {
        handler?.openSettings()
    }

    /// Whether the app declares a `Settings` scene to present: what the menu
    /// bar's Settings… item is shown by.
    @MainActor
    package var isAvailable: Bool {
        handler?.hasSettings() ?? false
    }

    /// Whether the two reach the same app, or are both outside one.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.handler === rhs.handler
    }
}

private struct OpenSettingsActionKey: EnvironmentKey {
    static let defaultValue = OpenSettingsAction(handler: nil)
}

extension EnvironmentValues {
    /// A Settings presentation action stored in a view's environment — mirrors
    /// SwiftUI's `openSettings`.
    ///
    /// The running app puts its own here; read outside one, it presents
    /// nothing.
    public package(set) var openSettings: OpenSettingsAction {
        get { self[OpenSettingsActionKey.self] }
        set { self[OpenSettingsActionKey.self] = newValue }
    }
}
