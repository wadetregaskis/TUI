//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+TooltipStyle.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Modifiers

extension View {
    /// Sets how tooltips in this subtree are presented.
    ///
    /// ```swift
    /// ContentView().tooltipStyle(.popover)
    /// ```
    public func tooltipStyle(_ style: TooltipStyle) -> some View {
        environment(\.tooltipStyle, style)
    }

    /// Sets when tooltips in this subtree appear.
    ///
    /// `help(_:)` still compiles and still publishes under
    /// ``TooltipTrigger/never``; nothing draws it. That is deliberate — the
    /// alternative is a modifier whose effect depends on where in the tree the
    /// reader happens to look.
    public func tooltips(_ trigger: TooltipTrigger) -> some View {
        environment(\.tooltipTrigger, trigger)
    }

    /// Sets how long the pointer must rest on a view before its tooltip
    /// appears.
    ///
    /// Does not affect the help key, which reveals the focused view's tooltip
    /// at once — a key press has already waited.
    ///
    /// - Parameter seconds: The delay. Clamped at zero when read.
    public func tooltipDelay(_ seconds: Double) -> some View {
        environment(\.tooltipDelay, seconds)
    }
}
