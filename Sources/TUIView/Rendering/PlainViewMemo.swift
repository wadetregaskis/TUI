//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainViewMemo.swift
//
//  A memo on the plain composites of an app: what stops a body running on a
//  frame in which nothing it depends on changed, as SwiftUI's does not.
//  `TUI_RUN_BODY_ON_EVERY_FRAME=1` turns it off. See
//  Documentation/Working notes/plain-body-memo-study.md.
//
//  It is the value memo (`renderValueMemoized`, `measureValueMemoized`), and so
//  its journal, its leases, its verifiers, its store gates and its invalidations
//  apply as they do to an `.equatable()` view. What is new is the key.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

/// The switch, and which types are memoized. Main-actor only, as the cache's
/// tables are.
package final class PlainMemo {
    /// Whether composites are memoized under this cache. Read once a process
    /// from `TUI_RUN_BODY_ON_EVERY_FRAME`; a test sets it per cache.
    package var isOn = PlainMemo.isOnByDefault

    private static let isOnByDefault = ProcessInfo.processInfo.environment["TUI_RUN_BODY_ON_EVERY_FRAME"] != "1"

    /// Which measures are timed.
    private var sampler = TimingSampler()

    /// The instant to time this measure from, if it is sampled.
    @inline(__always)
    func startTiming() -> ContinuousClock.Instant? {
        guard isOn else { return nil }
        return sampler.startTiming()
    }

    /// Each type asked about: how its values compare, or `nil` for one that is
    /// not memoized.
    private var roots: [ObjectIdentifier: ValueComparison?] = [:]

    /// The passes begun: what a cooldown is counted in.
    private var pass = 0

    /// The identity of the entry stored last, by its filed hash: whether the memo
    /// that just drew stored what it drew (``noteDrawn(at:)``), as nothing else
    /// below it can have stored last.
    var lastStored = 0

    /// How many value memos (`.equatable()`, a `ForEach` row) are drawing or
    /// measuring what they hold around this point in the walk. Inside one, the
    /// memo's value says whether its subtree changed, and it has a buffer and a size
    /// for it. Asking again costs a key, a kept scope and a store at each composite,
    /// which for a cheap one is more than its body: 6% of `session/notes`. So only a
    /// composite that's seen to take real time asks (``asksInsideValueMemo(_:)``).
    /// One does, since a row can be dropped where what it holds would still be served:
    /// a row that isn't `Equatable` goes when its parent writes, and a page of them is
    /// `tree-root`, 2 ms against 19.
    var valueMemoDepth = 0

    /// The types seen to take ``heavySubtree`` to measure, whole, inside a value memo.
    private var heavyTypes: Set<ObjectIdentifier> = []

    /// How many timed measures running each other type has been over the line. A
    /// type's first is its metadata being made, and any one can be preempted, and a
    /// row of a few `Text`s that got in on that would pay for asking from then on.
    private var overTheLine: [ObjectIdentifier: Int] = [:]

    /// Worth asking for: several times what a miss adds. `session/notes`'s rows of two
    /// `Text`s and a `Spacer` are well under it, and `tree-root`'s of 80 well over. A
    /// debug build's times are many times a release build's, so that's a line of its
    /// own, and a test that means to go over it sets it.
    #if DEBUG
        package var heavySubtree = Duration.milliseconds(5)
    #else
        package var heavySubtree = Duration.microseconds(100)
    #endif

    /// What each composite that has failed to be served has come to.
    private var gates: [Int: Gate] = [:]

    private struct Gate {
        /// Times running that what was kept could not be served, or nothing could
        /// be kept.
        var run = 0
        /// The pass until which it is left out of the memo.
        var until = 0
        /// The pass it last stored in.
        var stored = -1
    }

    /// What stores earn nothing. A composite that has to be drawn every frame (its
    /// data moves, or something under it writes, or holds what cannot be replayed)
    /// still pays to look, to observe, to record and to keep, and is served nothing.
    /// That is 5 of the 6 ms a frame `session/notes` lost.
    ///
    /// So one that has failed twice running stops asking, for 4, 8 … at most 64
    /// passes, as a re-check's cooldown does (``RevalidationState/noteVerdict(_:at:)``),
    /// and its children go on asking for themselves. Not a hit rate, and not a
    /// guess at a subtree's cost: both were tried in August and both were wrong
    /// (§28, where `anyview` won 34.8% on a 1.4% hit rate). A composite that is
    /// served once is never cooled, and one that settles waits at most 64 passes.
    package var counts = Counts()

    /// See ``counts``.
    package struct Counts: Equatable {
        /// Composites drawn straight through, cooling down.
        package var cooled = 0
    }

    package init() {}

    /// Whether a composite of `V` inside a value memo goes to the memo.
    @inline(__always)
    func asksInsideValueMemo<V: View>(_: V.Type) -> Bool {
        !heavyTypes.isEmpty && heavyTypes.contains(ObjectIdentifier(V.self))
    }

    /// Notes how long a composite of `V` inside a value memo took to measure, where
    /// that was timed.
    @inline(__always)
    func noteMeasured<V: View>(_: V.Type, since start: ContinuousClock.Instant?) {
        guard let start else { return }
        let type = ObjectIdentifier(V.self)
        guard ContinuousClock.now - start >= heavySubtree else {
            if !overTheLine.isEmpty { overTheLine[type] = nil }
            return
        }
        let seen = overTheLine[type, default: 0] + 1
        overTheLine[type] = seen
        if seen >= 3 { heavyTypes.insert(type) }
    }

    /// Starts a pass.
    func beginPass() {
        sampler.beginPass()
        pass &+= 1
        if pass.isMultiple(of: 64), !gates.isEmpty { gates = gates.filter { $0.value.until >= pass - 64 || $0.value.stored >= pass - 64 } }
    }

    /// The pass in which the cache was last emptied.
    private var clearedAt = Int.min

    /// Notes that the cache is being emptied, as it is when the terminal answers
    /// a question, a type is first seen to read something, or a change is made
    /// under another transaction than the one pending. The misses that follow say
    /// nothing of what a composite will do, so the pass it is emptied in and the
    /// next count as no evidence: counted, the frames of a program's start cooled
    /// a page of slow bodies for its first few keys.
    ///
    /// What was counted before stays counted. Forgetting it, as this once did,
    /// let `session/glides` ask again after each of its animated changes, which
    /// each empty the cache: a page whose glides keep it from being stored, and a
    /// clock that changes every frame, asked on 1 frame in 3 and were never served.
    func noteCleared() {
        clearedAt = pass
    }

    /// Whether the composite filed under `hash` is left out of the memo this pass.
    @inline(__always)
    func isCoolingDown(_ hash: Int) -> Bool {
        guard !gates.isEmpty, let gate = gates[hash] else { return false }
        return gate.until > pass
    }

    /// Notes what a draw at `hash` came to: it served, or it drew and either stored
    /// or could not. A store is no evidence until the next pass says whether it was
    /// any use, which is the pass after a cooldown ends too, so that a composite
    /// that has settled is served again.
    @inline(__always)
    func noteDrawn(at hash: Int, served: Bool) {
        if served {
            if !gates.isEmpty { gates[hash] = nil }
            return
        }
        noteMissed(at: hash)
    }

    @inline(never)
    private func noteMissed(at hash: Int) {
        var gate = gates[hash] ?? Gate()
        let storedNow = lastStored == hash
        let evidence = (!storedNow || gate.stored == pass - 1) && pass > clearedAt &+ 1
        if storedNow { gate.stored = pass }
        if evidence {
            gate.run += 1
            if gate.run >= 2 { gate.until = pass + min(64, 1 << min(gate.run, 6)) }
        }
        gates[hash] = gate
    }

    /// The comparison for a composite of `V`, or `nil` when it is not memoized:
    /// one of the framework's own (``FrameworkModules``), or holding something
    /// that cannot be compared.
    @inline(__always)
    func comparison<V: View>(forRoot type: V.Type, plans: ValueHashPlans) -> ValueComparison? {
        if let known = roots[ObjectIdentifier(type)] { return known }
        return decide(type, plans: plans)
    }

    @inline(never)
    private func decide(_ type: Any.Type, plans: ValueHashPlans) -> ValueComparison? {
        let made = FrameworkModules.declares(type) ? nil : plans.comparison(for: type)
        roots[ObjectIdentifier(type)] = .some(made)
        return made
    }
}

/// Where a plain composite's entries are filed beside a value memo's at the same
/// identity, which a row and its content share (`RenderCache.scopedEntry`).
let plainMemoSlot = 0x5F3A_91C7

/// What a plain composite's memo is keyed by, in the frame in which nothing above
/// it wrote: its fields, a closure or a `Binding` among them ignored, since its
/// bytes differ every time it is made and by purity its parent built the same
/// one; and the environment it is drawn under, by stamp, on every hit (an
/// `.equatable()` view trusts what is noted instead, which for these fails: the
/// study's point 5).
struct PlainKey<V: View> {
    let view: V
    let comparison: ValueComparison
    let plans: ValueHashPlans
    let stamp: EnvironmentStamp?
}

extension PlainKey: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = lhs.stamp, let right = rhs.stamp, left === right || left.isEquivalent(to: right) else {
            return false
        }
        return lhs.comparison.equal(lhs.view, rhs.view, strict: false, plans: lhs.plans)
    }
}

/// What a suspect is re-checked by, below a parent's write: compared strictly, so
/// a closure is changed, since it may have captured what was written. SwiftUI
/// looks through the closure and eventually does better; TUI cannot see into one,
/// and this cannot draw a wrong cell by giving up.
struct PlainRow<V: View> {
    let view: V
    let comparison: ValueComparison
    let plans: ValueHashPlans
}

extension PlainRow: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.comparison.equal(lhs.view, rhs.view, strict: true, plans: lhs.plans)
    }
}

extension RenderContext {
    /// The comparison a plain composite of `V`'s memo would use here, or `nil`
    /// when there is no memo: it is off, standalone rendering, or `V` is not
    /// memoized.
    @inline(__always)
    @MainActor
    func plainMemoComparison<V: View>(of _: V.Type) -> ValueComparison? {
        guard let cache = renderCache, cache.plainMemo.isOn, cache.volatileReadTracker != nil else { return nil }
        return cache.plainMemo.comparison(forRoot: V.self, plans: cache.valueHashPlans)
    }
}

/// ``renderToBuffer(_:context:)``'s composite branch, through the memo.
@inline(never)
@MainActor
func renderPlainMemoized<V: View>(
    _ view: V, comparison: ValueComparison, context: RenderContext, render: (V, RenderContext) -> FrameBuffer
) -> FrameBuffer {
    let cache = unsafe context.renderCache.unsafelyUnwrapped
    let memo = cache.plainMemo
    if memo.valueMemoDepth > 0, !memo.asksInsideValueMemo(V.self) { return render(view, context) }
    let hash = context.identity.structuralHash ^ plainMemoSlot
    if memo.isCoolingDown(hash) {
        memo.counts.cooled += 1
        return render(view, context)
    }
    let plans = cache.valueHashPlans
    let renderedBefore = cache.rowWork.rendered
    let buffer = renderValueMemoized(
        key: PlainKey(
            view: view, comparison: comparison, plans: plans,
            stamp: cache.revalidation.stamps.stamp(of: context.environment)),
        viewType: V.self, context: context, slot: plainMemoSlot,
        build: { PlainRow(view: view, comparison: comparison, plans: plans) },
        render: { render($0.view, $1) })
    memo.noteDrawn(at: hash, served: cache.rowWork.rendered == renderedBefore)
    return buffer
}

/// `measureChild`'s composite branch, through the memo.
@inline(never)
@MainActor
func measurePlainMemoized<V: View>(
    _ view: V, comparison: ValueComparison, proposal: ProposedSize, context: RenderContext,
    measure: (V, RenderContext) -> ViewSize
) -> ViewSize {
    let cache = unsafe context.renderCache.unsafelyUnwrapped
    let memo = cache.plainMemo
    if memo.valueMemoDepth > 0, !memo.asksInsideValueMemo(V.self) {
        let started = memo.startTiming()
        let size = measure(view, context)
        memo.noteMeasured(V.self, since: started)
        return size
    }
    if memo.isCoolingDown(context.identity.structuralHash ^ plainMemoSlot) { return measure(view, context) }
    let plans = cache.valueHashPlans
    return measureValueMemoized(
        key: PlainKey(
            view: view, comparison: comparison, plans: plans,
            stamp: cache.revalidation.stamps.stamp(of: context.environment)),
        proposal: proposal, context: context, slot: plainMemoSlot,
        build: { PlainRow(view: view, comparison: comparison, plans: plans) },
        measure: { measure($0.view, $1) })
}
