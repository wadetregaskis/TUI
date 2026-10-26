//  🖥️ TUI — A Terminal UI framework for Swift
//  ChildIdentityStep.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// What tells a container's child apart from its siblings, without the view:
/// enough to see whether a container's children are the ones it had last frame,
/// and to work out a child's identity under the container when that is asked.
///
/// For a container's memory of where it put its children (``PlacementStore``).
/// Kept instead of the ``ChildView``, which holds the view value and everything
/// that value holds — a model, a closure — alive for as long as it is kept; and
/// instead of the identity, which is a node allocated per child, where this is
/// a few words copied out of the child.
///
/// Two steps are equal when they would put a child at the same place as
/// written: the same type, index, key and namespace, and the same identity
/// already resolved, compared by its structural hash so that comparing a
/// resolved row walks no chain. The same child can be written two ways — a
/// `ForEach` resolves its rows ahead of use from sixteen rows on — so a
/// container that finds no match by step looks again by
/// ``identity(under:)``.
package struct ChildIdentityStep: Hashable {
    let type: Any.Type?
    let index: Int
    let key: String?
    let slot: Int32
    let resolved: ViewIdentity?

    /// The child's identity under the container at `parent` — exactly the one
    /// it measures and renders at (``ChildView/identity(under:)``).
    package func identity(under parent: ViewIdentity) -> ViewIdentity {
        if let resolved { return resolved }
        guard let type else { return parent }
        return ChildView.identity(of: type, index: index, key: key, slot: slot, under: parent)
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type.map(ObjectIdentifier.init) == rhs.type.map(ObjectIdentifier.init)
            && lhs.index == rhs.index && lhs.key == rhs.key && lhs.slot == rhs.slot
            && lhs.resolved?.structuralHash == rhs.resolved?.structuralHash
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(type.map(ObjectIdentifier.init))
        hasher.combine(index)
        hasher.combine(key)
        hasher.combine(slot)
        hasher.combine(resolved?.structuralHash)
    }
}
