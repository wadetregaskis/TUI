//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBodyKeep.swift
//
//  The bodies of the composites above a live `TimelineView`, kept from one
//  frame to the next, so that an entry of the timeline runs the timeline's
//  content and not every body on the way down to it.
//
//  No buffer above a live timeline can be kept: its render asks for the wake
//  of its next entry, a registration no memo makes again, so every memo that
//  contains it draws again at every entry, and a composite drawn again ran its
//  `body`. At sixty entries a second that was every body from the app's down to
//  a game's loop, and whatever their initialisers made (tuiarcade's
//  TUI-FEEDBACK.md, M2 item 2: a maze built sixty times a second). SwiftUI runs
//  the timeline's content alone. Here what the body built is kept beside the
//  value it was built from and the environment it was built under, and a
//  composite whose value and environment compare equal, as the plain memo
//  compares them, is walked from what it built last frame: its layout and its
//  drawing run, and its `body` does not. Its siblings below are served from
//  their own memos as before.
//
//  What drops a kept body is what would make it differ: a write to the view's
//  own `@State`, a change to an `@Observable` its body read, a clear of the
//  view or of anything above it (an environment modifier's, a parent's write),
//  as each drops a buffer kept there. A write BELOW it does not, since nothing
//  below a view changes what its `body` builds: SwiftUI's rule, by which a
//  leaf's write runs the leaf. The scopes its evaluation armed live as long as
//  it is kept (its lease), so a later write to what it read still finds it.
//
//  A body is kept where it is evaluated after such a frame: at its draw, or
//  at the measure before it where the measure keeps what it evaluated for
//  the draw (`BodyKeep`), since that draw takes the measure's and evaluates
//  nothing to keep. Kept only at the draw, a body `BodyKeep` keeps (a slow
//  type's, a stack's child) was never kept across frames, and ran at every
//  entry of the timeline below it (VIEWR-3).
//
//  Only an app's own composite the plain memo could compare, whose
//  properties read nothing the walk decides (`BodyKeep.mayKeepAcrossFrames`),
//  whose evaluation read nothing volatile, and only after a frame has shown a
//  live timeline below it: the walk an app with no timeline makes is unchanged,
//  beyond one look at an empty table.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

/// The bodies kept across frames above live timelines. Main-actor only, as
/// the cache's tables are.
package final class FrameBodyKeep {
    /// Whether bodies are kept across frames. A test sets it per cache;
    /// `TUI_KEEP_TIMELINE_ANCESTORS=0` turns it off, to compare.
    package var isOn = FrameBodyKeep.isOnByDefault

    private static let isOnByDefault = ProcessInfo.processInfo.environment["TUI_KEEP_TIMELINE_ANCESTORS"] != "0"

    /// One allocation for the key and the body: the key holds the view, so an
    /// address in its bytes cannot come back for another value while kept.
    private final class Box<V: View> {
        let key: PlainKey<V>
        let body: V.Body

        init(key: PlainKey<V>, body: V.Body) {
            self.key = key
            self.body = body
        }
    }

    private struct Kept {
        let identity: ViewIdentity
        let viewType: ObjectIdentifier
        let box: AnyObject
        let lease: ObservationLease?
        /// The pass it was last kept or taken in: one neither in a pass is gone.
        var pass: Int
    }

    private var table: [Int: Kept] = [:]

    /// The identities a frame drew a live timeline below, whose next draw
    /// evaluates its body to be kept: by hash, with the pass it was seen in.
    private var wanted: [Int: Int] = [:]

    private var pass = 0

    /// Whether a timeline asked for a wake in this pass or the one before:
    /// until one has, a composite's draw does not look at its timeline
    /// wakes at all, so a page with no timeline pays one load a composite.
    package private(set) var timelinesLive = false

    private var timelineSeenThisPass = false

    /// Says that a live timeline drew in this pass (``timelinesLive``).
    @inline(__always)
    package func noteLiveTimeline() {
        timelineSeenThisPass = true
        timelinesLive = true
    }

    /// What it has done: what the tests read.
    package struct Counts: Equatable {
        package var kept = 0
        package var taken = 0
        package var dropped = 0
    }

    package var counts = Counts()

    /// How many bodies are kept, for a census of the caches.
    package var count: Int { table.count }

    package init() {}

    /// Whether there is anything to look for, or to keep.
    @inline(__always)
    var isIdle: Bool { table.isEmpty && wanted.isEmpty }

    /// Starts a pass: what the pass before neither kept nor took has left the
    /// tree, or no longer has a live timeline below it.
    func beginPass() {
        pass &+= 1
        timelinesLive = timelineSeenThisPass
        timelineSeenThisPass = false
        if !table.isEmpty {
            let before = table.count
            table = table.filter { $0.value.pass >= pass - 1 }
            counts.dropped &+= before - table.count
        }
        if !wanted.isEmpty { wanted = wanted.filter { $0.value >= pass - 1 } }
    }

    /// Whether a body is kept at `identity`: what to ask before building a key.
    @inline(__always)
    func holds(_ identity: ViewIdentity) -> Bool {
        !table.isEmpty && table[identity.structuralHash] != nil
    }

    /// Whether `identity`'s next evaluation is to be kept.
    @inline(__always)
    func wants(_ identity: ViewIdentity) -> Bool {
        !wanted.isEmpty && wanted[identity.structuralHash] != nil
    }

    /// Notes that a live timeline was drawn below `identity`, whose body was
    /// not kept: the next draw keeps it.
    func want(_ identity: ViewIdentity) {
        guard isOn else { return }
        wanted[identity.structuralHash] = pass
    }

    /// Keeps `body`, which `key`'s view built at `identity` under the lease
    /// `lease` holds its scopes by.
    func keep<V: View>(_ body: V.Body, key: PlainKey<V>, identity: ViewIdentity, lease: ObservationLease?) {
        guard isOn else { return }
        counts.kept &+= 1
        wanted[identity.structuralHash] = nil
        table[identity.structuralHash] = Kept(
            identity: identity, viewType: ObjectIdentifier(V.self), box: Box(key: key, body: body), lease: lease,
            pass: pass)
    }

    /// Notes that what was kept at `identity` was walked again this pass, and
    /// still has a live timeline below it.
    func touch(_ identity: ViewIdentity) {
        table[identity.structuralHash]?.pass = pass
    }

    /// Lets go of what is kept at `identity`: it no longer has a live timeline
    /// below it, so the plain memo can keep its buffer.
    func forget(_ identity: ViewIdentity) {
        if table.removeValue(forKey: identity.structuralHash) != nil { counts.dropped &+= 1 }
    }

    /// What was kept for a view at `identity` whose key compares equal with
    /// `key`, or `nil`.
    func take<V: View>(_ key: PlainKey<V>, identity: ViewIdentity, leases: ObservationLeases) -> V.Body? {
        guard let kept = table[identity.structuralHash], kept.viewType == ObjectIdentifier(V.self),
            kept.identity == identity
        else { return nil }
        let box = unsafe unsafeDowncast(kept.box, to: Box<V>.self)
        guard box.key == key else {
            table[identity.structuralHash] = nil
            counts.dropped &+= 1
            return nil
        }
        counts.taken &+= 1
        table[identity.structuralHash]?.pass = pass
        leases.use(kept.lease)
        return box.body
    }

    /// Drops what is kept at `identity` and, when `includingDescendants`, below
    /// it: never above it, since nothing below a view changes what its body
    /// builds.
    func drop(at identity: ViewIdentity, includingDescendants: Bool) {
        guard !table.isEmpty else { return }
        let before = table.count
        table = table.filter { _, kept in
            !(kept.identity == identity || (includingDescendants && identity.isAncestor(of: kept.identity)))
        }
        counts.dropped &+= before - table.count
    }

    /// Drops everything kept.
    func dropAll() {
        counts.dropped &+= table.count
        table.removeAll()
        wanted.removeAll()
    }
}

// MARK: - The walk's side

/// What a draw of a composite does with ``FrameBodyKeep``: whether its body is
/// to be evaluated for keeping, and what to keep it under.
struct FrameBodyPlan<V: View> {
    let key: PlainKey<V>
    let mark: Int?
    let unsafeBefore: Int
}

extension RenderContext {
    /// The key a composite's body would be kept under across frames, if it may
    /// be kept at all.
    @MainActor
    func frameBodyKey<V: View>(of view: V) -> PlainKey<V>? {
        guard let cache = renderCache, cache.plainMemo.frameBodies.isOn,
            let comparison = plainMemoComparison(of: V.self),
            cache.bodyKeep.mayKeepAcrossFrames(V.self)
        else { return nil }
        let plans = cache.valueHashPlans
        return PlainKey(
            view: view, comparison: comparison, plans: plans,
            stamp: cache.revalidation.stamps.stamp(of: environment))
    }
}

/// The body a composite kept across frames at `context`'s identity, prepared
/// as an evaluation would have left the view, or `nil`.
@MainActor
func frameKeptBody<V: View>(of view: V, context: RenderContext) -> V.Body? {
    guard let cache = context.renderCache, cache.plainMemo.frameBodies.holds(context.identity),
        let key = context.frameBodyKey(of: view),
        let body = cache.plainMemo.frameBodies.take(key, identity: context.identity, leases: cache.leases)
    else { return nil }
    if let plan = propertyPlan(for: V.self) {
        var prepared = view
        prepareProperties(
            of: &prepared, plan: plan, identity: context.identity, storage: context.stateStorage,
            environment: context.environment, isMeasuring: context.isMeasuring)
    }
    context.stateStorage?.markActive(context.identity)
    return body
}

/// A measure of the body kept across frames at `context`'s identity, or `nil`
/// when none is kept for `view`. Out of line, so the measure of a composite
/// with nothing kept asks the runtime for no `V.Body?` metadata.
@inline(never)
@MainActor
func measureFrameKeptBody<V: View>(
    _ view: V, proposal: ProposedViewSize, context: RenderContext, childContext: RenderContext
) -> ViewSize? {
    guard let kept = frameKeptBody(of: view, context: context) else { return nil }
    return measureChild(kept, proposal: proposal, context: childContext)
}

/// Where a draw is to keep the body it evaluates: a view a live timeline was
/// drawn below last frame. Opens the computation the body's scopes are leased
/// to, which ``keepFrameBody(_:plan:context:)`` closes.
@MainActor
func beginFrameBody<V: View>(of view: V, context: RenderContext) -> FrameBodyPlan<V>? {
    guard !context.isMeasuring, let cache = context.renderCache, !cache.plainMemo.frameBodies.isIdle,
        cache.plainMemo.frameBodies.wants(context.identity), let key = context.frameBodyKey(of: view)
    else { return nil }
    return FrameBodyPlan(
        key: key, mark: cache.leases.beginComputation(),
        unsafeBefore: context.environment.volatileReadTracker?.cacheUnsafeCount ?? 0)
}

/// Closes what ``beginFrameBody(of:context:)`` opened, keeping `body` unless
/// its evaluation read something volatile. Whether it kept it.
@MainActor
func keepFrameBody<V: View>(_ body: V.Body, plan: FrameBodyPlan<V>, context: RenderContext) -> Bool {
    guard let cache = context.renderCache else { return false }
    let lease = cache.leases.endComputation(plan.mark)
    guard (context.environment.volatileReadTracker?.cacheUnsafeCount ?? 0) == plan.unsafeBefore else { return false }
    cache.plainMemo.frameBodies.keep(body, key: plan.key, identity: context.identity, lease: lease)
    return true
}

/// Keeps across frames what a measure evaluated to keep for this pass's draw
/// (`BodyKeep`), at a view a live timeline was drawn below last frame: the
/// draw would take the pass's keep and never come to keep its own. Whether
/// it kept it; if not, the pass's keep is the caller's.
///
/// The measure's body is one `BodyKeep` hands the draw, so it is one the
/// draw may be walked from, and a kept body is prepared again on the view of
/// each walk that takes it. Not kept: one whose evaluation read something
/// volatile, as at the draw; and one under an environment with no stamp,
/// whose key compares equal with none, so that the draw, finding nothing it
/// can take here, takes the pass's keep (`ab701fc43`'s case).
///
/// Out of line, so a measure that keeps for the pass alone asks the runtime
/// for no `PlainKey<V>?` metadata.
@inline(never)
@MainActor
func keepMeasuredFrameBody<V: View>(
    _ body: V.Body, of view: V, lease: ObservationLease?, unsafeBefore: Int, context: RenderContext
) -> Bool {
    guard let cache = context.renderCache, let key = context.frameBodyKey(of: view), key.stamp != nil,
        (context.environment.volatileReadTracker?.cacheUnsafeCount ?? 0) == unsafeBefore
    else { return false }
    cache.plainMemo.frameBodies.keep(body, key: key, identity: context.identity, lease: lease)
    return true
}

/// The count a composite's draw reads before and after, to learn whether a
/// live timeline was drawn below it: the frame's tracker, which every memo
/// below shares. `nil` while measuring, which asks for no wake.
@inline(__always)
@MainActor
func timelineWakesSoFar(_ context: RenderContext) -> Int? {
    guard !context.isMeasuring, let cache = context.renderCache, cache.plainMemo.frameBodies.isOn else { return nil }
    return cache.volatileReadTracker?.timelineWakes
}

/// After a composite's draw: what was drawn below it says whether its body is
/// worth keeping across frames.
/// A framework composite (a stack, a modifier, the timeline itself) is never
/// wanted: it could not be kept, and its body only forwards.
@MainActor
func noteFrameBody<V: View>(of _: V.Type, at context: RenderContext, timelineWakesBefore: Int?, kept: Bool) {
    guard let timelineWakesBefore, let cache = context.renderCache else { return }
    let frameBodies = cache.plainMemo.frameBodies
    let live = (cache.volatileReadTracker?.timelineWakes ?? 0) != timelineWakesBefore
    if live {
        if kept {
            frameBodies.touch(context.identity)
        } else if cache.bodyKeep.mayKeepAcrossFrames(V.self), context.plainMemoComparison(of: V.self) != nil {
            frameBodies.want(context.identity)
        }
    } else if kept {
        frameBodies.forget(context.identity)
    }
}
