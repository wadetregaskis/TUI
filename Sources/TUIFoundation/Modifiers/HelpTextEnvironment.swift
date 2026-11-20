//  🖥️ TUI — A Terminal UI framework for Swift
//  HelpTextEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Help Text Environment

/// EnvironmentKey for the help text in force for a subtree.
private struct HelpTextKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The help text a focusable control inside this subtree should claim as its
    /// own, or `nil`.
    ///
    /// This is how the FOCUS half of `help(_:)` reaches the control:
    /// ``View/help(_:)`` writes it for its content, and
    /// `FocusRegistration.register(context:handler:focusID:)` — which every
    /// focusable control funnels through — publishes it when that control holds
    /// the focus. The alternative was to read `\.isFocused` in the modifier,
    /// which does not work: `isFocused` is published INSIDE a control's own
    /// render, so `Button("Save") {}.help("…")` — the natural spelling, with the
    /// modifier outside — would never see it.
    ///
    /// Innermost wins, because this is an ordinary environment cascade.
    package var helpText: String? {
        get { self[HelpTextKey.self] }
        set { self[HelpTextKey.self] = newValue }
    }
}

// MARK: - The Help Inside a Focus Stop

/// The help written inside a focused `.focusable()` view, gathered for it as
/// its content draws: what the help key shows while the view holds the focus
/// (``EnvironmentValues/focusStopHelp``).
@MainActor
package final class FocusStopHelp {
    /// The innermost `help(_:)` drawn inside the view so far this frame — the
    /// last one drawn — or `nil`.
    package var text: String?

    package init() {}
}

/// EnvironmentKey for the help a focused focus stop gathers from its content.
///
/// Render-neutral: a mailbox the helps inside post into, and nothing draws
/// from it. A new one is handed down each frame the stop holds the focus, and
/// compared by identity it would have kept every memo inside a focused stop
/// from serving; a help that posts into it declares a render side effect
/// instead, so nothing that posted is stored.
private struct FocusStopHelpKey: EnvironmentKey, _RenderNeutralEnvironmentKey {
    static let defaultValue: FocusStopHelp? = nil
}

extension EnvironmentValues {
    /// Where a `help(_:)` drawn inside a focused `.focusable()` view leaves its
    /// text for that view, or `nil` outside one.
    ///
    /// ``helpText`` carries a help DOWN to the control it is written on or
    /// around, which publishes it as it registers; this carries one UP, from
    /// inside the view to the stop around it. `Rectangle().help("…")
    /// .focusable()` has its help inside the stop, which registers before its
    /// content draws, so the stop's own environment never had it, and the help
    /// key showed nothing where the pointer showed the tooltip. SwiftUI's view
    /// has one help however its modifiers are ordered.
    ///
    /// Set by the stop only while it holds the focus, and to `nil` by an
    /// unfocused one inside it, so a help reaches the stop nearest to it. A
    /// help that fills it declares a render side effect, so no memo between
    /// the two serves a frame that would not fill it again.
    package var focusStopHelp: FocusStopHelp? {
        get { self[FocusStopHelpKey.self] }
        set { self[FocusStopHelpKey.self] = newValue }
    }
}
