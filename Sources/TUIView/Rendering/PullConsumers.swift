//  🖥️ TUI — A Terminal UI framework for Swift
//  PullConsumers.swift
//
//  Which views in scroll content are pulled (SCROLL-FIT design, P2): the
//  lazy stacks that band themselves against a request, and the columns that
//  hold one and so place their children outward from an anchor. A column
//  asks it of each child it places — does a pulled view sit below this
//  child by single-child steps? — before it draws the child, which is how
//  it knows to hand the child a request rather than draw it whole.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// The pulled views a render cache has seen in scroll content, by identity.
///
/// Filed by each one's own measure, which a column always asks before it
/// places the child (`_VStackCore`): so the first frame knows, and a frame
/// served from a memo keeps what an earlier one filed. A view that stops being
/// pulled — a lazy stack whose data fell under the windowing threshold, a
/// column whose last pulled child went — withdraws itself the next time it is
/// measured. One that leaves the tree may leave its entry behind, which costs
/// only a column taking the pulled path for children that are all drawn whole,
/// and which draws them as the eager path would; the set is cleared past
/// ``capacity`` so that cannot grow without bound.
package struct PullConsumers {
    /// What a pulled view does with a request.
    package enum Kind: Sendable {
        /// Bands its own rows against it: a windowed lazy stack.
        case bandsRows
        /// Places its children outward from an anchor, handing a request on
        /// to those that are pulled: a column holding one.
        case pullsChildren
    }

    private var kinds: [ViewIdentity: Kind] = [:]
    /// How many filed views have each ``ViewIdentity/singleChildRoot``: what
    /// ``holdsConsumer(below:)`` asks, in one lookup, for a child reached by a
    /// sibling step.
    private var roots: [ViewIdentity: Int] = [:]

    /// More than any page holds in view; past it the set starts over, and the
    /// views in it file themselves again as they are measured.
    package static let capacity = 4_096

    package init() {}

    /// Files `identity` as pulled, of `kind`, or withdraws it (`nil`).
    package mutating func note(_ identity: ViewIdentity, as kind: Kind?) {
        guard kinds[identity] != kind else { return }
        if let kind {
            if kinds.count >= Self.capacity {
                kinds.removeAll(keepingCapacity: true)
                roots.removeAll(keepingCapacity: true)
            }
            if kinds.updateValue(kind, forKey: identity) == nil {
                roots[identity.singleChildRoot, default: 0] += 1
            }
        } else if kinds.removeValue(forKey: identity) != nil {
            let root = identity.singleChildRoot
            if let count = roots[root], count > 1 { roots[root] = count - 1 } else { roots[root] = nil }
        }
    }

    /// Whether no view is filed: no page in this cache has pulled anything.
    package var isEmpty: Bool { kinds.isEmpty }

    /// What `identity` does with a request, or `nil` when it is not pulled.
    package func kind(of identity: ViewIdentity) -> Kind? { kinds[identity] }

    /// Whether a pulled view sits below `child` by single-child steps — at
    /// it, or under any number of bodies and modifiers that draw it — so that a
    /// request handed to `child` reaches it.
    package func holdsConsumer(below child: ViewIdentity) -> Bool {
        guard !kinds.isEmpty else { return false }
        if child.isSiblingStep { return roots[child] != nil }
        // A child reached by a single-child step — a column of one statically
        // typed view — shares its root with what is below it, so the root
        // cannot tell; asked of each filed view instead, which is rare.
        return kinds.keys.contains { $0.isDirectDescent(from: child) }
    }
}
