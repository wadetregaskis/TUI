//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DismissBehavior.swift
//
//  SwiftUI's `DismissBehavior` and `Transaction.dismissBehavior`: whether a
//  `dismissWindow` closes a window that is showing a sheet or an alert.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Programmatic window dismissal behaviors — mirrors SwiftUI's
/// `DismissBehavior`.
///
/// Set one on the transaction a ``DismissWindowAction`` is called in:
///
/// ```swift
/// struct DismissWindowButton: View {
///     @Environment(\.dismissWindow) private var dismissWindow
///
///     var body: some View {
///         Button("Close Auxiliary Window") {
///             withTransaction(\.dismissBehavior, .destructive) {
///                 dismissWindow(id: "auxiliary")
///             }
///         }
///     }
/// }
/// ```
///
/// As on macOS: under ``interactive``, the default, a window showing a modal
/// presentation — a sheet, a full-screen cover, an alert or a confirmation
/// dialog, which hold its keyboard — is not dismissed; under ``destructive``
/// it is, its presentations with it. A popover or an open menu is not a modal
/// presentation, and does not keep a window open.
public struct DismissBehavior: Sendable, Equatable {
    /// Whether a window showing a modal presentation is dismissed too.
    let isDestructive: Bool

    /// The interactive dismiss behavior — the default — that does not dismiss
    /// a window showing a modal presentation, as a person closing it could
    /// not.
    public static let interactive = Self(isDestructive: false)

    /// The destructive dismiss behavior, that dismisses a window regardless of
    /// what it is showing; what its presentations held is lost with them.
    public static let destructive = Self(isDestructive: true)
}

extension Transaction {
    /// The behavior of a window dismissal made under this transaction —
    /// mirrors SwiftUI's `Transaction.dismissBehavior`. ``DismissBehavior/interactive``
    /// unless set.
    public var dismissBehavior: DismissBehavior {
        get { dismissesDestructively ? .destructive : .interactive }
        set { dismissesDestructively = newValue.isDestructive }
    }
}
