//  🖥️ TUI — A Terminal UI framework for Swift
//  CombinedSubmitAction.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

// MARK: - Combined submit action

/// Assembles a text field's effective submit action from its own per-field
/// closure and the cascading `.onSubmit(of:_:)` actions that match `role`.
///
/// Order matches SwiftUI's accumulation: the most-specific action runs first —
/// the per-field ``TextField/onSubmit(_:)`` closure, then the cascading env
/// actions inner-first (i.e. reversed relative to the outer-first append order).
///
/// Returns `nil` when there is nothing to run, which is load-bearing: a
/// ``TextField`` with no submit action lets Return fall through to a dialog's
/// default button (see ``TextFieldHandler``), so a non-nil no-op would silently
/// break default buttons.
func combinedSubmitAction(
    perField: (() -> Void)?,
    cascading actions: [SubmitActionEntry],
    role: SubmitTriggers
) -> (() -> Void)? {
    let matching = actions.filter { !$0.triggers.isDisjoint(with: role) }
    guard perField != nil || !matching.isEmpty else { return nil }
    return {
        AmbientApp.renderState?.noteControlActivated()
        perField?()
        // Inner-first: the environment appends outer-first, so a descendant's
        // `.onSubmit` is later in the array and must fire before an ancestor's.
        for entry in matching.reversed() { entry.action() }
    }
}
