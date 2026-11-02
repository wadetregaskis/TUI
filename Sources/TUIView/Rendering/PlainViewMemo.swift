//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainViewMemo.swift
//
//  A memo on the plain composites of an app: what stops a body running on a
//  frame in which nothing it depends on changed, as SwiftUI's does not. Off
//  unless `TUI_PLAIN_MEMO=1`. See Documentation/Working notes/plain-body-memo-study.md.
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
    /// from `TUI_PLAIN_MEMO`; a test sets it per cache.
    package var isOn = PlainMemo.isOnByDefault

    private static let isOnByDefault = ProcessInfo.processInfo.environment["TUI_PLAIN_MEMO"] == "1"

    /// Each type asked about: how its values compare, or `nil` for one that is
    /// not memoized.
    private var roots: [ObjectIdentifier: ValueComparison?] = [:]

    /// The passes begun: what a cooldown is counted in.
    private var pass = 0

    /// The identity of the entry stored last, by its filed hash: whether the memo
    /// that just drew stored what it drew (``noteDrawn(at:)``), as nothing else
    /// below it can have stored last.
    var lastStored = 0

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

    /// Starts a pass.
    func beginPass() {
        pass &+= 1
        if pass.isMultiple(of: 64), !gates.isEmpty { gates = gates.filter { $0.value.until >= pass - 64 || $0.value.stored >= pass - 64 } }
    }

    /// Forgets what has failed: the cache is being emptied, as it is when the
    /// terminal answers a question or a type is first seen to read something, which
    /// says nothing of what its composites will do. Left counted, the frames of a
    /// program's start cooled a page of slow bodies for its first few keys.
    func forgetAttempts() {
        if !gates.isEmpty { gates.removeAll(keepingCapacity: true) }
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
        let evidence = !storedNow || gate.stored == pass - 1
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
    let cache = context.renderCache.unsafelyUnwrapped
    let memo = cache.plainMemo
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
    let cache = context.renderCache.unsafelyUnwrapped
    if cache.plainMemo.isCoolingDown(context.identity.structuralHash ^ plainMemoSlot) {
        return measure(view, context)
    }
    let plans = cache.valueHashPlans
    return measureValueMemoized(
        key: PlainKey(
            view: view, comparison: comparison, plans: plans,
            stamp: cache.revalidation.stamps.stamp(of: context.environment)),
        proposal: proposal, context: context, slot: plainMemoSlot,
        build: { PlainRow(view: view, comparison: comparison, plans: plans) },
        measure: { measure($0.view, $1) })
}
