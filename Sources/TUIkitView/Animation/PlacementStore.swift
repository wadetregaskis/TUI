//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PlacementStore.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// Where each container last placed its children, so that a change of layout
/// under an animation can move them from there instead of jumping.
///
/// ## Why a container has to remember
///
/// SwiftUI animates every view's frame: inside `withAnimation`, a row inserted
/// above another pushes it down by gliding it, and a row removed lets the ones
/// below glide up into its space (measured, `plan/fb16/samples.txt`: a sibling
/// below an inserted row moved 187 → 194 → 202 → 218 → 234 → 247 over an 8 s
/// linear animation, for every transition, `.identity` included). A terminal
/// rebuilds its whole frame from the tree, so on the frame of the change the
/// tree says only where each child IS — where it was is gone unless something
/// kept it. This is what keeps it: one record per container, holding what each
/// child is and where it was drawn when the container last rendered.
///
/// The motion itself is not here. A child that has to move is given a value in
/// the ``AnimationStore`` — its placement, keyed by its identity — so a glide
/// is interrupted, merged, held still by reduce motion and waited on by a
/// `withAnimation` completion exactly as every other animated value is. This
/// store is only the memory those glides start from.
///
/// ## What keeps a record alive
///
/// Not re-declaration, which is how the ``AnimationStore`` prunes. A container
/// whose subtree a memo serves is not rendered, so it re-declares nothing —
/// and its record, pruned, made the next change a first sight, which never
/// moves anything. That is the commonest shape there is: a page re-rendered
/// because something ELSE on it changed, its stacks served, then the change
/// that matters. So a record lives while its container renders, or while a
/// memo serves a subtree it stands in (``retainServedSubtree(_:)``): the one
/// way a container is on screen without being rendered.
///
/// Not for as long as `@State` lives, which also outlasts a window's skip
/// (`StateStorage.retainSubtree(_:)`: the rows a `List` scrolled past, a
/// collapsed `DisclosureGroup`'s content, a toolbar's hidden items). What
/// those hold is not drawn, so where it was drawn is a place nobody has seen
/// since: when it comes back it is placed directly, as SwiftUI places a view
/// it inserts, not glided from wherever it stood when it went. And kept, a
/// record per stack in every row a list had been scrolled through was a table
/// that grew with the scrolling, which ``endRenderPass()`` walked every frame.
///
/// Main-actor by discipline rather than by annotation, exactly as
/// ``StateStorage`` is — it is a stored property of one, and rendering is
/// single-threaded on the run loop.
public final class PlacementStore: @unchecked Sendable {

    /// One container's memory of its children.
    ///
    /// A class, so a container that finds its record mutates it where it lies
    /// rather than copying it out and writing it back: a container whose
    /// layout has not changed, which is nearly all of them on nearly every
    /// frame, writes nothing at all.
    package final class Record {
        /// The container's children as it last laid them out, in order — the
        /// departing ones aside.
        package var entries: [ChildPlacementEntry]

        /// The identities of ``entries``, worked out the first time a change
        /// needed them and kept while the children stay the same: a glide asks
        /// for its child's on every frame it moves.
        package var identities: [ViewIdentity]?

        /// Which of ``entries`` are moving, or `nil` when none is — the one
        /// question a settled container's frame asks.
        package var gliding: [Bool]?

        /// Where each child that is leaving was drawn when it left, and at
        /// what z-index, keyed by what it was among the children.
        package var departed: [ChildIdentityStep: (placement: ChildPlacement, zIndex: Double)] = [:]

        /// The pass this record was last asked about.
        package var lastPass: UInt64

        /// The pass and walk it was first made in. A change in a LATER walk of
        /// that same pass is still its appearance — the walk before was never
        /// shown — and moves nothing, as ``AnimationStore`` treats a value.
        package let appeared: (pass: UInt64, walk: UInt64)

        init(entries: [ChildPlacementEntry], pass: UInt64, walk: UInt64) {
            self.entries = entries
            self.lastPass = pass
            self.appeared = (pass, walk)
        }
    }

    private var records: [ViewIdentity: Record] = [:]

    /// Which pass is being rendered — see ``AnimationStore``'s, which this
    /// copies rather than shares, so that each store prunes by its own.
    private var pass: UInt64 = 0

    /// How many records this pass has asked about or made: when that is all
    /// of them, nothing can be stale and the end of the pass looks at none.
    private var askedThisPass = 0

    /// The subtrees a memo served this pass (``retainServedSubtree(_:)``).
    private var servedRoots: [ViewIdentity] = []

    /// Creates an empty store.
    public init() {}

    /// How many containers are remembered (tests, diagnostics).
    public var count: Int { records.count }
}

extension PlacementStore {
    /// The record of the container at `identity`, stamped as asked about this
    /// pass, or `nil` the first time it is seen.
    package func record(at identity: ViewIdentity) -> Record? {
        guard let record = records[identity] else { return nil }
        if record.lastPass != pass {
            record.lastPass = pass
            askedThisPass += 1
        }
        return record
    }

    /// Remembers `entries` as the container at `identity` first lays them out,
    /// on `walk` of the pass.
    package func remember(_ entries: [ChildPlacementEntry], at identity: ViewIdentity, walk: UInt64) {
        let replaced = records.updateValue(Record(entries: entries, pass: pass, walk: walk), forKey: identity)
        if replaced?.lastPass != pass { askedThisPass += 1 }
    }

    /// Whether `record` was made in this pass, on a walk other than `walk`.
    package func appearedEarlierThisPass(_ record: Record, walk: UInt64) -> Bool {
        record.appeared.pass == pass && record.appeared.walk != walk
    }

    /// Starts a pass.
    ///
    /// Called from ``StateStorage/beginRenderPass()``.
    public func beginRenderPass() {
        pass &+= 1
        askedThisPass = 0
        servedRoots.removeAll(keepingCapacity: true)
    }

    /// Declares that a memo served the subtree at `root` this pass: the
    /// containers below it are on screen as they last drew, so their records
    /// are kept though none of them rendered.
    ///
    /// Called where a memo serves (`renderValueMemoized`) — beside
    /// `StateStorage.retainSubtree(_:)`, which a window that skips its rows
    /// calls too, and that one is not this: see "What keeps a record alive".
    package func retainServedSubtree(_ root: ViewIdentity) {
        servedRoots.append(root)
    }

    /// Forgets the containers that neither rendered this pass nor stand in a
    /// subtree a memo served.
    ///
    /// Called from ``StateStorage/endRenderPass()``. Nothing to look at on a
    /// pass that asked about every record, which is every pass no memo
    /// served a container on. Collect-then-remove, the spelling
    /// ``AnimationStore/endRenderPass()`` uses and says why.
    package func endRenderPass() {
        guard records.count > askedThisPass else { return }
        var served = RetainedSubtreeIndex(roots: servedRoots)
        var stale: [ViewIdentity] = []
        for (identity, record) in records where record.lastPass != pass {
            if !served.retains(identity) { stale.append(identity) }
        }
        for identity in stale { records.removeValue(forKey: identity) }
    }

    /// Forgets everything.
    public func removeAll() {
        records.removeAll()
        askedThisPass = 0
    }
}

// MARK: - What is remembered of a child

/// Where a container drew a child, in cells from the container's top-leading
/// corner.
package struct ChildPlacement: Equatable, Sendable {
    package var x: Int
    package var y: Int

    package init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// The placement as an animatable value, for the ``AnimationStore``.
    var animatable: AnimatablePair<Double, Double> {
        AnimatablePair(Double(x), Double(y))
    }

    /// The cell a placement part-way through a glide is drawn at.
    init(_ value: AnimatablePair<Double, Double>) {
        self.init(x: Int(value.first.rounded()), y: Int(value.second.rounded()))
    }
}

/// One child as a container last laid it out: what it is, where it went, and
/// how it stacks against its siblings.
package struct ChildPlacementEntry: Equatable {
    package var step: ChildIdentityStep
    package var placement: ChildPlacement
    package var zIndex: Double

    package init(step: ChildIdentityStep, placement: ChildPlacement, zIndex: Double) {
        self.step = step
        self.placement = placement
        self.zIndex = zIndex
    }
}
