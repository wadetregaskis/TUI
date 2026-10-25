//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusManager+FocusState.swift
//
//  The focus manager's side of `@FocusState`: which control a store's value
//  is bound to, and moving the focus when the value is set.
//
//  Created by Wade Tregaskis
//  License: MIT

extension FocusManager {
    /// The value whose bound control currently holds focus, for a store — the
    /// getter behind `@FocusState`. `nil` (the empty value) when none does.
    func focusedValue(forStore store: String) -> AnyHashable? {
        guard let focused = currentFocusedID, let map = focusBindings[store] else { return nil }
        return map.first { $0.value.focusID == focused }?.key
    }

    /// Moves focus to the control bound to `value` for a store, or — when
    /// `value` is `nil` (the empty value) — relinquishes focus if one of the
    /// store's controls currently holds it. The setter behind `@FocusState`,
    /// called from event closures (outside a render pass).
    func setFocusValue(_ value: AnyHashable?, forStore store: String) {
        pendingFocusValues[store] = nil
        let map = focusBindings[store] ?? [:]
        if let value, let binding = map[value] {
            focus(id: binding.focusID)
        } else if let value {
            // No control bound to it has registered yet: it may be appearing in
            // this pass (``pendingFocusValues``).
            pendingFocusValues[store] = (value, focusRenderGeneration)
        } else if let focused = currentFocusedID, map.values.contains(where: { $0.focusID == focused }) {
            relinquishFocus()
        }
    }
}
