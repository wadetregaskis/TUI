//  🖥️ TUI — A Terminal UI framework for Swift
//  View+SelectionDisabled.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Selection Disabled Modifier

extension View {
    // `@inlinable`, with the modifier's initializer (module split, step C3):
    // a sidebar tab view in TUITabs calls this for every row it lists,
    // and across the module boundary that call is generic over the row's
    // type, so it reached this module unspecialised. The result type is
    // public, so an app sees no more of it than it did.
    /// Disables selection for this view within a List.
    ///
    /// Applied to a list row, this row cannot become the `List`'s selection —
    /// Enter/Space and a click on it do nothing — and it renders with a
    /// dimmed foreground to show it. Up/Down, Page Up/Page Down and Home/End
    /// also route around it, once it has rendered at least once: like
    /// ``View/deleteDisabled(_:)`` / ``View/moveDisabled(_:)``, the refusal is
    /// reported to the enclosing `List` as the row draws, so a row that has
    /// never been on screen has not yet had the chance to report and cannot
    /// yet be routed around.
    ///
    /// # Example
    ///
    /// ```swift
    /// List(selection: $selection) {
    ///     ForEach(items) { item in
    ///         Text(item.name)
    ///             .selectionDisabled(item.isLocked)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter isDisabled: Whether selection should be disabled. Default is `true`.
    /// - Returns: A view with selection disabled state applied.
    @inlinable
    nonisolated public func selectionDisabled(_ isDisabled: Bool = true) -> some View {
        SelectionDisabledModifier(content: self, isDisabled: isDisabled)
    }
}
