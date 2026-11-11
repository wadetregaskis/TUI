//  🖥️ TUI — A Terminal UI framework for Swift
//  Scene+SettingsPanel.swift
//
//  What an app says of the settings panel: hides or replaces TUI's own tabs,
//  and moves the panel's key. TUI-specific, kept apart from SwiftUI's
//  `Settings` scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - TUI's Own Tabs

/// One of the tabs TUI adds to the settings panel after the app's own.
///
/// TUI-specific: SwiftUI's apps take these from the system's settings.
public enum BuiltInSettingsTab: Hashable, Sendable, CaseIterable {
    /// View: the palette, the border style and the control style, then
    /// Breathing Focus, Spell Out Keys, Focus Follows Pointer and Arrows
    /// Follow Layout, as the menu bar's View menu offers them.
    case view

    /// Accessibility: Differentiate Without Color, Reduce Motion, Reduce
    /// Transparency and Increase Contrast, the View menu's checks.
    case accessibility
}

/// What the app said of one of TUI's tabs.
enum BuiltInSettingsTabChoice {
    /// Shown, as by default.
    case shown
    /// Left out.
    case hidden
    /// The app's own content in its place, under the tab's title.
    case replaced(AnyView)

    /// Whether the panel has the tab at all.
    var isShown: Bool {
        if case .hidden = self { return false }
        return true
    }
}

// MARK: - Public Modifiers

extension Scene {
    /// Shows or hides one of the tabs TUI adds to the settings panel after
    /// the app's own.
    ///
    /// Both are shown by default. An app with good reason may leave either
    /// out — it offers the same choices itself, say:
    ///
    /// ```swift
    /// WindowGroup { EditorView() }
    ///     .builtInSettingsTab(.view, visibility: .hidden)
    /// ```
    ///
    /// App-wide, as the panel is: read from any of the app's scenes, the
    /// `Settings` scene's statement first, then the window scenes' in the
    /// order they are declared. With no tab left at all, the panel has nothing
    /// to show: F2 does nothing and the menu bar has no Settings….
    ///
    /// TUI-specific.
    ///
    /// - Parameters:
    ///   - tab: The tab.
    ///   - visibility: `.hidden` to leave it out; `.visible` or `.automatic`
    ///     to show it.
    /// - Returns: A scene that says so.
    public func builtInSettingsTab(_ tab: BuiltInSettingsTab, visibility: Visibility) -> some Scene {
        _SettingsPanelStatement(content: self) {
            $0.builtInSettingsTabs[tab] = visibility == .hidden ? .hidden : .shown
        }
    }

    /// Replaces one of the tabs TUI adds to the settings panel with content
    /// of the app's own, under the same title.
    ///
    /// ```swift
    /// WindowGroup { EditorView() }
    ///     .builtInSettingsTab(.accessibility) { EditorAccessibilitySettings() }
    /// ```
    ///
    /// App-wide, read as ``Scene/builtInSettingsTab(_:visibility:)`` is.
    ///
    /// TUI-specific.
    ///
    /// - Parameters:
    ///   - tab: The tab.
    ///   - content: What the tab shows instead.
    /// - Returns: A scene that says so.
    public func builtInSettingsTab<Content: View>(
        _ tab: BuiltInSettingsTab, @ViewBuilder content: () -> Content
    ) -> some Scene {
        let replacement = AnyView(content())
        return _SettingsPanelStatement(content: self) { $0.builtInSettingsTabs[tab] = .replaced(replacement) }
    }

    /// Moves the key that opens the settings panel, F2 by default, or takes
    /// it away.
    ///
    /// F2 is a default binding: answered in the input chain's last layer, so
    /// an app that binds F2 itself gets it first, and needs nothing from this.
    /// Use it to put the panel on another key, or with `nil` to claim none.
    /// The panel is still reached by ⌃, (the `Settings` scene's ⌘, through the
    /// command key), the menu bar's Settings…, a `SettingsLink` and
    /// `openSettings`.
    ///
    /// ```swift
    /// WindowGroup { EditorView() }
    ///     .settingsPanelKey(.f3)
    /// ```
    ///
    /// App-wide, read as ``Scene/builtInSettingsTab(_:visibility:)`` is.
    /// TUI-specific, as the help key's `TooltipState.helpKey` is.
    ///
    /// - Parameter key: The key, or `nil` for none.
    /// - Returns: A scene whose settings panel opens on `key`.
    public func settingsPanelKey(_ key: Key?) -> some Scene {
        _SettingsPanelStatement(content: self) { $0.settingsPanelKey = .some(key) }
    }
}

// MARK: - Wrapper Scene

/// Framework-internal scene wrapper that states something of the settings
/// panel into its scene's configuration.
internal struct _SettingsPanelStatement<Content: Scene>: Scene {
    let content: Content
    let statement: @MainActor (inout SceneConfiguration) -> Void

    /// A primitive scene: it renders through `SceneRenderable`.
    var body: Never { fatalError("_SettingsPanelStatement renders via SceneRenderable") }
}

extension _SettingsPanelStatement: ConfiguringScene {
    /// The modifier closest to the scene wins, as every scene modifier's.
    func configure(_ configuration: inout SceneConfiguration) {
        statement(&configuration)
    }

    var configuredContent: (any Scene)? { content }
}

extension _SettingsPanelStatement: SceneRenderable {
    func renderScene(context: RenderContext) -> FrameBuffer {
        content.renderSceneTree(context: context)
    }
}
