//  🖥️ TUI — A Terminal UI framework for Swift
//  SubmitEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - Submit action entry

/// One ``View/onSubmit(of:_:)`` registration cascading through the
/// environment: the triggers it responds to plus the action to run, a plain
/// closure, as every action closure in the framework is (Button,
/// `TextField.onSubmit`, …).
package struct SubmitActionEntry {
    package let triggers: SubmitTriggers
    package let action: () -> Void
}

// MARK: - Environment keys

/// The stack of `.onSubmit(of:_:)` actions in scope, outer-first (append order).
/// A text field runs the ones whose triggers match its role, inner-first.
private struct SubmitActionsKey: EnvironmentKey {
    static var defaultValue: [SubmitActionEntry] { [] }
}

/// Which submit trigger a field in this subtree represents — ``SubmitTriggers/text``
/// for a normal ``TextField`` / ``SecureField``, ``SubmitTriggers/search`` for the
/// `.searchable` query field. Selects which cascading actions the field consumes.
/// The KEY is private (internal plumbing), but the property is package-visible so
/// `SearchableModifier` can scope its query field to `.search`.
private struct SubmitTriggerRoleKey: EnvironmentKey {
    static let defaultValue: SubmitTriggers = .text
}

extension EnvironmentValues {
    /// The cascading `.onSubmit(of:_:)` actions in scope (outer-first). Read by
    /// text fields to assemble their effective submit action.
    package var submitActions: [SubmitActionEntry] {
        get { self[SubmitActionsKey.self] }
        set { self[SubmitActionsKey.self] = newValue }
    }

    /// The submit trigger a field in this subtree represents (default ``SubmitTriggers/text``).
    package var submitTriggerRole: SubmitTriggers {
        get { self[SubmitTriggerRoleKey.self] }
        set { self[SubmitTriggerRoleKey.self] = newValue }
    }
}
