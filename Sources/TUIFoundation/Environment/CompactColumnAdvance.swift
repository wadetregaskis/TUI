//  🖥️ TUI — A Terminal UI framework for Swift
//  CompactColumnAdvance.swift
//
//  How a list in a collapsed `NavigationSplitView` shows the next column: the
//  split hands the column on top this action, and choosing a row runs it, as
//  tapping a row does on iPhone (decisions A21, B3). Here, below both the
//  split view and the list, because neither module can see the other.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Shows the next column of a collapsed `NavigationSplitView`.
///
/// Equal by identity, as ``DismissAction`` is: the split keeps one box for its
/// life and refreshes the action in it, so the environment holds the same value
/// every frame and the memos below the column stay on.
package struct CompactColumnAdvance: Equatable {
    private let box: DismissAction.Box

    package init(box: DismissAction.Box) {
        self.box = box
    }

    @MainActor
    package func callAsFunction() {
        box.action()
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.box === rhs.box
    }
}

private struct CompactColumnAdvanceKey: EnvironmentKey {
    static let defaultValue: CompactColumnAdvance? = nil
}

extension EnvironmentValues {
    /// The way to the next column of the collapsed `NavigationSplitView` whose
    /// column on top this is, or `nil` anywhere else — a split that is not
    /// collapsed, its last column, or outside any split.
    package var compactColumnAdvance: CompactColumnAdvance? {
        get { self[CompactColumnAdvanceKey.self] }
        set { self[CompactColumnAdvanceKey.self] = newValue }
    }
}
