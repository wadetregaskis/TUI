//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SubmitEnvironment.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Submit action entry

/// One ``View/onSubmit(of:_:)`` registration cascading through the
/// environment: the triggers it responds to plus the action to run. It wraps a
/// plain (non-`Sendable`) closure; `@unchecked Sendable` is sound because the
/// action is only ever created and invoked on the render loop's single thread —
/// the same latitude every action closure in the framework relies on (Button,
/// `TextField.onSubmit`, …). This lets `submitActions` be a concurrency-safe
/// empty-array default.
struct SubmitActionEntry: @unchecked Sendable {
    let triggers: SubmitTriggers
    let action: () -> Void
}

// MARK: - Environment keys

/// The stack of `.onSubmit(of:_:)` actions in scope, outer-first (append order).
/// A text field runs the ones whose triggers match its role, inner-first.
private struct SubmitActionsKey: EnvironmentKey {
    static let defaultValue: [SubmitActionEntry] = []
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
    var submitActions: [SubmitActionEntry] {
        get { self[SubmitActionsKey.self] }
        set { self[SubmitActionsKey.self] = newValue }
    }

    /// The submit trigger a field in this subtree represents (default ``SubmitTriggers/text``).
    var submitTriggerRole: SubmitTriggers {
        get { self[SubmitTriggerRoleKey.self] }
        set { self[SubmitTriggerRoleKey.self] = newValue }
    }
}
