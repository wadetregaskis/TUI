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
/// that grew with the scrolling.
///
/// ## When records are forgotten
///
/// Not every pass. Telling a record a memo served from one nothing rendered
/// takes a structural compare against every served root, and a page whose
/// memos serve something on every frame — nearly every page — paid it for
/// every record on every frame: 81.5% of a `fanout` frame, and that scenario
/// +557% (Time Profiler, 2026-10-18, `PlacementStore.endRenderPass` under
/// `StateStorage.endRenderPass`). So the table is pruned only when it has
/// grown past ``pruneThreshold`` — twice what the last prune left, and never
/// below ``minimumPruneThreshold`` — which a page whose containers stay the
/// same never reaches, and which a list scrolled through reaches once per
/// doubling: amortised, a constant per record. Until then a record that
/// went off screen lingers, and a container that renders again after a pass
/// in which it was neither rendered nor served is a first sight, its record
/// made afresh (``record(at:)``): it went, and it is back as a view SwiftUI
/// inserts. Read, the lingering record faded out the rows its container had
/// lost while it was gone and glided the rest from places nobody had seen
/// since — `if show { Column() }`, its rows changed while hidden, shown again
/// under an animation.
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

        /// Where each child that has come to draw nothing is drawn while its
        /// glide runs — where it was — keyed by what it is among the
        /// children; empty when nothing moves. See
        /// ``RenderContext/glidingPlacements(of:drawing:at:departing:)``.
        package var held: [ChildIdentityStep: ChildPlacement] = [:]

        /// What each of ``entries`` drew when the container last rendered: the
        /// picture a child that has gone fades out from (`ChildFade`), there
        /// being nothing else of it left. `nil` for a spacer.
        ///
        /// Written on every frame the container renders, settled or not: the
        /// frame a child goes is the first that does not draw it, so what it
        /// looked like has to have been kept on the one before. A store of the
        /// array the container already holds, a retain and a release.
        package var pictures: [FrameBuffer?]

        /// Which of ``entries`` are fading in, or `nil` when none is — the
        /// question a settled container's frame asks beside ``gliding``.
        package var arriving: [Bool]?

        /// The children that have gone and are still leaving: fading out from
        /// their last picture, or playing a transition of their own. Empty,
        /// nearly always.
        package var leaving: [LeavingChild] = []

        /// The pass this record was last asked about.
        package var lastPass: UInt64

        /// The pass and walk it was first made in. A change in a LATER walk of
        /// that same pass is still its appearance — the walk before was never
        /// shown — and moves nothing, as ``AnimationStore`` treats a value.
        package let appeared: (pass: UInt64, walk: UInt64)

        init(entries: [ChildPlacementEntry], pictures: [FrameBuffer?], pass: UInt64, walk: UInt64) {
            self.entries = entries
            self.pictures = pictures
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

    /// The subtrees a memo served on the pass before this one, and an index of
    /// them made the first time this pass asks (``wasServedLastPass(_:)``).
    private var servedRootsLastPass: [ViewIdentity] = []
    private var servedLastPassIndex: RetainedSubtreeIndex?

    /// The fewest records a prune is run at: see "When records are
    /// forgotten".
    package static let minimumPruneThreshold = 512

    /// How many records the table may hold before the end of a pass prunes
    /// it: twice what the last prune left, and at least
    /// ``minimumPruneThreshold``.
    private(set) package var pruneThreshold = PlacementStore.minimumPruneThreshold

    /// Creates an empty store.
    public init() {}

    /// How many containers are remembered (tests, diagnostics).
    public var count: Int { records.count }
}

extension PlacementStore {
    /// The record of the container at `identity`, stamped as asked about this
    /// pass, or `nil` the first time it is seen — and the first time it is
    /// seen again after a pass it was not on screen: neither rendered nor in
    /// a subtree a memo served. Such a record is of a frame nobody has seen
    /// since, and is dropped (see "When records are forgotten").
    package func record(at identity: ViewIdentity) -> Record? {
        guard let record = records[identity] else { return nil }
        if record.lastPass != pass {
            guard record.lastPass == pass &- 1 || wasServedLastPass(identity) else {
                records.removeValue(forKey: identity)
                return nil
            }
            record.lastPass = pass
            askedThisPass += 1
        }
        return record
    }

    /// Whether the view at `identity` stood in a subtree a memo served on the
    /// pass before this one — on screen as it was last drawn, though nothing
    /// in it rendered. Asked of a record a pass went by without, which is
    /// rare: a container rendered on every pass never asks.
    package func wasServedLastPass(_ identity: ViewIdentity) -> Bool {
        guard !servedRootsLastPass.isEmpty else { return false }
        // Taken out while it is asked, so the verdicts it keeps are written
        // in place rather than into a copy.
        var index = servedLastPassIndex ?? RetainedSubtreeIndex(roots: servedRootsLastPass)
        servedLastPassIndex = nil
        defer { servedLastPassIndex = index }
        return index.retains(identity) || servedRootsLastPass.contains(identity)
    }

    /// Remembers `entries`, drawing `pictures`, as the container at `identity`
    /// first lays them out, on `walk` of the pass.
    package func remember(
        _ entries: [ChildPlacementEntry], pictures: [FrameBuffer?], at identity: ViewIdentity, walk: UInt64
    ) {
        let record = Record(entries: entries, pictures: pictures, pass: pass, walk: walk)
        let replaced = records.updateValue(record, forKey: identity)
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
        swap(&servedRoots, &servedRootsLastPass)
        servedRoots.removeAll(keepingCapacity: true)
        servedLastPassIndex = nil
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

    /// Once the table has outgrown ``pruneThreshold``, forgets the
    /// containers that neither rendered this pass nor stand in a subtree a
    /// memo served, and sets the next threshold from what is left.
    ///
    /// Called from ``StateStorage/endRenderPass()``. Below the threshold it
    /// looks at nothing — see "When records are forgotten" for why not every
    /// pass. Collect-then-remove, the spelling
    /// ``AnimationStore/endRenderPass()`` uses and says why.
    package func endRenderPass() {
        guard records.count > pruneThreshold, records.count > askedThisPass else { return }
        var served = RetainedSubtreeIndex(roots: servedRoots)
        var stale: [ViewIdentity] = []
        for (identity, record) in records where record.lastPass != pass {
            if !served.retains(identity) { stale.append(identity) }
        }
        for identity in stale { records.removeValue(forKey: identity) }
        pruneThreshold = max(Self.minimumPruneThreshold, 2 * records.count)
    }

    /// Forgets everything.
    public func removeAll() {
        records.removeAll()
        servedRootsLastPass.removeAll()
        servedLastPassIndex = nil
        askedThisPass = 0
        pruneThreshold = Self.minimumPruneThreshold
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

/// One child as a container last laid it out: what it is, where it went, how
/// it stacks against its siblings, and whether it drew anything there.
package struct ChildPlacementEntry: Equatable {
    package var step: ChildIdentityStep
    package var placement: ChildPlacement
    package var zIndex: Double
    /// Whether it drew no rows or no columns: what it shows, if anything, is
    /// what it carries past its frame.
    package var drawsNothing: Bool
    /// Whether it was the slot of a view still leaving (`ChildView.isDeparting`),
    /// laid out by a container that holds a removal's room: when the slot
    /// goes, the removal has played, and nothing is left to fade.
    package var isDeparting: Bool
    /// The type of the view it was — what a transition of its own was left by,
    /// where its step does not say (`ChildFade`). Read once a child has gone.
    package var viewType: Any.Type

    package init(
        step: ChildIdentityStep, placement: ChildPlacement, zIndex: Double, drawsNothing: Bool,
        isDeparting: Bool, viewType: Any.Type
    ) {
        self.step = step
        self.placement = placement
        self.zIndex = zIndex
        self.drawsNothing = drawsNothing
        self.isDeparting = isDeparting
        self.viewType = viewType
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.step == rhs.step && lhs.placement == rhs.placement && lhs.zIndex == rhs.zIndex
            && lhs.drawsNothing == rhs.drawsNothing && lhs.isDeparting == rhs.isDeparting
            && ObjectIdentifier(lhs.viewType) == ObjectIdentifier(rhs.viewType)
    }
}

/// A child that has gone from its container, still being drawn where it was
/// while it leaves — see `ChildFade`.
package struct LeavingChild {
    /// How it is drawn while it leaves.
    package enum Picture {
        /// The picture it drew on its last frame, faded by its presence: the
        /// default transition, `.opacity`.
        case fading(FrameBuffer)
        /// The removal of a transition of its own, played from what it left
        /// in the `DepartureStore` at `identity`, by a view of `type`.
        case playing(identity: ViewIdentity, type: Any.Type)
    }

    /// What it was among the children.
    package var step: ChildIdentityStep
    /// Where it is drawn: where it was when it went.
    package var placement: ChildPlacement
    /// How it stacked against its siblings.
    package var zIndex: Double
    package var picture: Picture
}
