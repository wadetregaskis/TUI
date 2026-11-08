//  🖥️ TUI — A Terminal UI framework for Swift
//  TabView+Settings.swift
//
//  A tab view as a `Settings` scene's content: its tabs become the settings
//  panel's first tabs.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

extension TabView: SettingsTabsProviding {
    /// Each tab the strip would show, by its title — `nil`, the app's name,
    /// for a tab whose label is not text — with its content: the tabs a
    /// `Settings { TabView { … } }` gives the settings panel, as SwiftUI's
    /// settings window shows a tab view's tabs in its toolbar.
    package var settingsTabs: [SettingsTab] {
        tabs.filter { !$0.isHidden }.map { tab in
            SettingsTab(title: tab.title.isEmpty ? nil : tab.title, content: tab.content)
        }
    }
}
