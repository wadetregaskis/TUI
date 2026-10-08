//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HelpTextEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

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
    var helpText: String? {
        get { self[HelpTextKey.self] }
        set { self[HelpTextKey.self] = newValue }
    }
}
