//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsLink.swift
//
//  SwiftUI's `SettingsLink`: a button that presents the app's `Settings`
//  scene.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The Link

/// A view that opens the Settings scene defined by an app — mirrors SwiftUI's
/// `SettingsLink`.
///
/// ```swift
/// SettingsLink()
///
/// SettingsLink {
///     Label("Preferences", systemImage: "slider.horizontal.3")
/// }
/// ```
///
/// A button that calls ``EnvironmentValues/openSettings``: the app's
/// `Settings` scene comes up as a sheet over the window in front. Its label is
/// a button's, styled by the `.buttonStyle` and `.labelStyle` around it.
public struct SettingsLink<Label: View>: View {
    let label: Label

    @Environment(\.openSettings) private var openSettings

    public var body: some View {
        Button {
            openSettings()
        } label: {
            label
        }
    }
}

extension SettingsLink where Label == DefaultSettingsLinkLabel {
    /// Creates a settings link with the default system label — mirrors
    /// SwiftUI's `init()`: "Settings…", in the current language, with a gear.
    public init() {
        self.label = DefaultSettingsLinkLabel()
    }
}

extension SettingsLink {
    /// Creates a settings link with a custom label — mirrors SwiftUI's
    /// `init(label:)`.
    ///
    /// - Parameter label: A view to use as the label for this settings link.
    public init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }
}

// MARK: - The Default Label

/// The default label to use for a settings link — mirrors SwiftUI's
/// `DefaultSettingsLinkLabel`: "Settings…", as macOS titles the item, in the
/// current language, with a gear icon a `.labelStyle` can show or hide.
///
/// You don't use this type directly: ``SettingsLink``'s `init()` makes it.
public struct DefaultSettingsLinkLabel: View {
    /// Made by ``SettingsLink``'s `init()` only, as SwiftUI's is.
    init() {}

    public var body: some View {
        TUIFoundation.Label {
            Text(LocalizationService.shared.string(for: LocalizationKey.Menu.settings))
        } icon: {
            Image(systemName: "gearshape")
        }
    }
}

// MARK: - Environment without reflection

extension SettingsLink: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _openSettings.resolveEnvironment(environment)
    }
}
