//  🖥️ TUI — A Terminal UI framework for Swift
//  TabViewHiddenTabs.swift
//
//  The tabs a tab view is not showing keep their state for when it shows them
//  again.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension _TabViewCore {
    /// Keeps the state of the tabs not shown — a counter's count, a navigation
    /// stack's pushed screen — for when they are shown again, as SwiftUI's tab
    /// view does. Not drawn, a hidden tab's content was pruned at the end of
    /// the frame, and came back started over. Each tab is a branch of its own
    /// (`contentContext(_:stripHeight:available:)`), so what one keeps is never
    /// another's. Render passes only: a measure keeps nothing.
    func retainHiddenTabs(besides selectedIndex: Int, context: RenderContext) {
        guard !context.isMeasuring, let stateStorage = context.stateStorage else { return }
        for (index, tab) in tabs.enumerated() where index != selectedIndex {
            // The branch itself as well as what is below it: a retained subtree
            // is its root's strict descendants.
            let hidden = context.identity.branch("tab-\(tab.value)")
            stateStorage.markActive(hidden)
            stateStorage.retainSubtree(hidden)
        }
    }
}
