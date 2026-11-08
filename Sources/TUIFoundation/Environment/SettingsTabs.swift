//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsTabs.swift
//
//  The tabs an app's `Settings` scene gives the settings panel: one for each
//  of a `TabView`'s tabs, which a view of a higher module offers here.
//
//  Created by Wade Tregaskis
//  License: MIT

/// One tab of the app's own in the settings panel (TUIApp's `SettingsPanel`).
package struct SettingsTab {
    /// The tab's title in the panel's tab strip, or `nil` for the app's name.
    package let title: String?

    /// The tab's content.
    package let content: AnyView

    /// A tab titled `title`, or after the app where that is `nil`, showing
    /// `content`.
    package init(title: String?, content: AnyView) {
        self.title = title
        self.content = content
    }
}

/// A view whose content is tabs of its own — TUITabs' `TabView` — which the
/// settings panel shows as tabs of its own when it is a `Settings` scene's
/// content, rather than as one tab holding a tab view.
///
/// Here, below the module that has tab views, so the `Settings` scene can ask
/// its content without linking them.
package protocol SettingsTabsProviding {
    /// The tabs, in order, each with its content: the ones the view shows.
    @MainActor var settingsTabs: [SettingsTab] { get }
}
