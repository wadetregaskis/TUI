//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewDividerGrip.swift
//
//  Whether an HSplitView's or a VSplitView's dividers draw a grip.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

private struct SplitViewDividerGripKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
    /// Whether an ``HSplitView``'s or a ``VSplitView``'s dividers draw a grip —
    /// three `◦` at the middle of the rule, as a `NavigationSplitView`'s
    /// resizable divider draws them. Shown unless `.hidden`.
    ///
    /// Set via ``View/splitViewDividerGrip(_:)``.
    package var splitViewDividerGrip: Visibility {
        get { self[SplitViewDividerGripKey.self] }
        set { self[SplitViewDividerGripKey.self] = newValue }
    }
}

extension View {
    /// Shows or hides the grip on the dividers of the ``HSplitView``s and
    /// ``VSplitView``s in this view.
    ///
    /// A divider draws three `◦` at the middle of its rule by default, as a
    /// `NavigationSplitView`'s resizable divider does — the cue that it is
    /// there to be dragged, as every divider here is. `.hidden` leaves the
    /// plain rule, for a split whose panes the reader is not expected to
    /// resize, or one whose rule should read as a border.
    ///
    /// ```swift
    /// HSplitView { Navigator(); Editor() }
    ///     .splitViewDividerGrip(.hidden)
    /// ```
    ///
    /// TUI-specific: SwiftUI's split views draw the platform's divider.
    ///
    /// - Parameter visibility: `.hidden` for a plain rule; `.automatic` (the
    ///   default) or `.visible` for the grip.
    /// - Returns: A view whose split views draw their dividers so.
    public func splitViewDividerGrip(_ visibility: Visibility) -> some View {
        environment(\.splitViewDividerGrip, visibility)
    }
}
