//  🖥️ TUI — A Terminal UI framework for Swift
//  StateStorage+OptionalRecords.swift
//
//  The sweep of the `if` records (`OptionalPresence`): which go when a pass
//  did not write them, including those of rows a lazy stack, a `List` or a
//  `Table` has windowed out.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension StateStorage {
    /// Drops the records of the `if`s that did not render this pass, except
    /// those still worth something. Run from ``endRenderPass()`` once the
    /// table has doubled since the last run, as every sweep of these records
    /// is.
    ///
    /// A record is what an `if` last held, so that the frame after one that
    /// showed it can play an arrival or a departure, and so that the render
    /// that finds it empty drops the state of the view it held. An `if` that
    /// has left the tree goes, as it always did. An `if` in a row a window
    /// left out — retained (`retainSubtree(_:)`) and neither drawn nor served
    /// by a memo this pass — was kept whole, picture and all, for as long as
    /// its container lived, and with it the identity of every view down to
    /// it: Stress `titled-lazy`, a lazy stack of rows each with an `if`, held
    /// 500,000 identity nodes (40 MB) after 20 seconds of scrolling, and grew
    /// by about 1.7 KB a line scrolled. Of such a record only the last of its
    /// jobs can still matter: one a pass went by without plays nothing when
    /// its row comes back (``wasOnScreenLastPass(writtenOn:at:)``), and a new
    /// record behaves alike. So it goes, unless its `if` held a view that has
    /// state below it to drop — kept then without its picture, with the
    /// row's state, which lives as long as the container
    /// (`Row state lifetime (2026-10-29).md`).
    func sweepOptionalRecords(retained: inout RetainedSubtreeIndex) {
        let served = placements.servedThisPass()
        var stale: [ViewIdentity] = []
        var held: [ViewIdentity] = []
        for (identity, record) in optionalPresence where record.pass != currentPass {
            if !retained.retains(identity) || (!record.holds && !served(identity)) {
                stale.append(identity)
            } else if !served(identity) {
                held.append(identity)
            }
        }
        let holdingState = scopesHoldingState(held)
        for identity in held {
            if holdingState.contains(identity) {
                optionalPresence[identity]?.picture = nil
                optionalPresence[identity]?.arrival = nil
                optionalPresence[identity]?.returningFrom = nil
            } else {
                stale.append(identity)
            }
        }
        for identity in stale { optionalPresence.removeValue(forKey: identity) }
    }

    /// Which of `scopes` have state stored at them or below them — what
    /// ``dropOptionalContent(at:heldAt:)`` would drop. Each stored value's
    /// identity is climbed once, up to the shallowest scope, stopping at a
    /// node an earlier climb passed through; a scope is found when a climb
    /// reaches it. A raw-rooted scope, which has no chain to climb (ancestry
    /// is a prefix of its path), is asked of every stored value instead — a
    /// tree drawn without an app around it; an app's is rooted at its type.
    ///
    /// Nodes are told apart by their structural hash, as
    /// `RetainedSubtreeIndex` tells them: two nodes sharing one would stop a
    /// climb early and miss a scope, a record then dropped whose view's state
    /// would not be dropped with its `if` — at 64 bits, not seen.
    private func scopesHoldingState(_ scopes: [ViewIdentity]) -> Set<ViewIdentity> {
        guard !scopes.isEmpty else { return [] }
        var found: Set<ViewIdentity> = []
        var byHash: [Int: [ViewIdentity]] = [:]
        for scope in scopes {
            if scope.isRawRooted {
                let holds = { (identity: ViewIdentity) in identity == scope || scope.isAncestor(of: identity) }
                if values.keys.contains(where: { holds($0.identity) })
                    || trackedValues.keys.contains(where: { holds($0.identity) })
                {
                    found.insert(scope)
                }
            } else {
                byHash[scope.structuralHash, default: []].append(scope)
            }
        }
        guard let shallowest = byHash.values.joined().map(\.depth).min() else { return found }
        var climbed: Set<Int> = []
        func climb(from identity: ViewIdentity) {
            var cursor: ViewIdentity? = identity
            while let node = cursor, node.depth >= shallowest {
                guard climbed.insert(node.structuralHash).inserted else { return }
                if let matches = byHash[node.structuralHash] {
                    for scope in matches where scope == node { found.insert(scope) }
                }
                cursor = node.parent
            }
        }
        for key in values.keys { climb(from: key.identity) }
        for key in trackedValues.keys { climb(from: key.identity) }
        return found
    }
}
