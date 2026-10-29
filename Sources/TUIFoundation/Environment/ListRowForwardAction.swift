//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowForwardAction.swift
//
//  What → does on the row under a list's cursor, where the list is not a tree
//  and so has no use of its own for the key: a file panel's column view opens
//  the folder there, as Finder's does. Here, below both the list and the file
//  panels, because the list cannot see the panels.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Goes forward from the row under a list's cursor: given the row's id, does
/// what → means there and answers whether it did anything.
///
/// Equal by identity, as ``CompactColumnAdvance`` is: its owner keeps one box
/// for its life and refreshes the action in it, so the environment holds the
/// same value every frame and the memos below stay on.
package struct ListRowForwardAction: Equatable, Sendable {
    /// The action, refreshed in place by the box's owner.
    package final class Box: @unchecked Sendable {
        package var action: @MainActor (AnyHashable) -> Bool { get { _action } set { _action = newValue } }

        /// ``action``'s storage: private, under the `package` accessor
        /// (CONTRIBUTING.md, "Crossing a module boundary").
        private var _action: @MainActor (AnyHashable) -> Bool

        package init(_ action: @escaping @MainActor (AnyHashable) -> Bool = { _ in false }) {
            self._action = action
        }
    }

    private let box: Box

    package init(box: Box) {
        self.box = box
    }

    /// Goes forward from the row `id`; `false` where there is nowhere to go,
    /// and the key is left to whatever comes after the list.
    @MainActor
    package func callAsFunction(_ id: AnyHashable) -> Bool {
        box.action(id)
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.box === rhs.box
    }
}

private struct ListRowForwardActionKey: EnvironmentKey {
    static let defaultValue: ListRowForwardAction? = nil
}

extension EnvironmentValues {
    /// What → does on the row under the cursor of a list below that is not a
    /// tree, or `nil` for nothing: the key then leaves the list.
    package var listRowForwardAction: ListRowForwardAction? {
        get { self[ListRowForwardActionKey.self] }
        set { self[ListRowForwardActionKey.self] = newValue }
    }
}
