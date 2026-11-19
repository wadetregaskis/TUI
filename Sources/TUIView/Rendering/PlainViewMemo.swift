//  🖥️ TUI — A Terminal UI framework for Swift
//  PlainViewMemo.swift
//
//  A memo on the plain composites of an app: what stops a body running on a
//  frame in which nothing it depends on changed, as SwiftUI's does not.
//  `TUI_RUN_BODY_ON_EVERY_FRAME=1` turns it off. The study and the decision are
//  in Documentation/Historical/State and dynamic properties/When a body runs -
//  the plain-body memo.md.
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

    /// Whether a measure's time is read at all: see ``RenderCache/learnsFromTiming``.
    package var learnsFromTiming: Bool {
        get { sampler.isOn }
        set { sampler.isOn = newValue }
    }

    /// The instant to time this measure from, if it is sampled.
    @inline(__always)
    func startTiming() -> ContinuousClock.Instant? {
        guard isOn else { return nil }
        return sampler.startTiming()
    }

    /// Each type asked about: how its values compare, or `nil` for one that is
    /// not memoized.
    private var roots: [ObjectIdentifier: Root] = [:]

    /// What ``roots`` holds for a type: its comparison, and whether it is
    /// memoized only while a timeline is live (``_PlainMemoizedBesideTimelines``).
    private struct Root {
        let comparison: ValueComparison?
        let onlyBesideTimelines: Bool
    }

    /// The passes begun: what a cooldown is counted in.
    private var pass = 0

    /// The identity of the entry stored last, by its filed hash: whether the memo
    /// that just drew stored what it drew (``noteDrawn(at:served:measuring:)``),
    /// as nothing else below it can have stored last.
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
        /// The pass whose miss last counted in ``run``: a pass counts once.
        var counted = -1
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

    /// The bodies above live timelines, kept across frames by the plain
    /// memo's key: see ``FrameBodyKeep``. Dropped with everything the cache
    /// clears (``noteCleared()``).
    package let frameBodies = FrameBodyKeep()

    /// The layer composites kept across frames beside live timelines (`LayerCompositeKeep`).
    package let layerComposites = LayerCompositeKeep()

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
        frameBodies.beginPass()
        layerComposites.beginPass()
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
        frameBodies.dropAll()
        layerComposites.dropAll()
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
    ///
    /// What a frame says is what its drawn walk says, once. A draw while
    /// `measuring` is no evidence unless it served: nothing drawn there is ever
    /// stored (`RenderCache.isStorable`), so its miss says nothing of whether
    /// the drawn walk would be served. And a pass counts once, as a cooldown is
    /// counted in passes: a walk made again within it (`FrameSettling`) draws
    /// what the walk before it wrote over, and its miss is the same frame's.
    /// Counted per draw, an app's first frame, which measures by drawing and
    /// walks twice, was two failures running before it had drawn a second
    /// frame, and cooled its page through the frames after: `sheet-search`'s
    /// table behind the sheet was left out of the memo for the sheet's two
    /// opening frames, where it could have been stored, and Find drew it
    /// (PERFCASE-F15).
    @inline(__always)
    func noteDrawn(at hash: Int, served: Bool, measuring: Bool) {
        if served {
            if !gates.isEmpty { gates[hash] = nil }
            return
        }
        if measuring { return }
        noteMissed(at: hash)
    }

    @inline(never)
    private func noteMissed(at hash: Int) {
        var gate = gates[hash] ?? Gate()
        let storedNow = lastStored == hash
        let evidence = (!storedNow || gate.stored == pass - 1) && pass > clearedAt &+ 1 && gate.counted != pass
        if storedNow { gate.stored = pass }
        if evidence {
            gate.counted = pass
            gate.run += 1
            if gate.run >= 2 { gate.until = pass + min(64, 1 << min(gate.run, 6)) }
        }
        gates[hash] = gate
    }

    /// The comparison for a composite of `V`, or `nil` when it is not memoized:
    /// one of the framework's own (``FrameworkModules``) that is not a
    /// ``_PlainMemoizedFrameworkView``, or holding something that cannot be
    /// compared.
    ///
    /// A ``_PlainMemoizedBesideTimelines`` control is memoized only while a
    /// timeline is live (``FrameBodyKeep/timelinesLive``), and only while
    /// ``FrameBodyKeep/isOn``.
    @inline(__always)
    func comparison<V: View>(forRoot type: V.Type, plans: ValueHashPlans) -> ValueComparison? {
        let root = roots[ObjectIdentifier(type)] ?? decide(type, plans: plans)
        if root.onlyBesideTimelines, !(frameBodies.timelinesLive && frameBodies.isOn) { return nil }
        return root.comparison
    }

    @inline(never)
    private func decide(_ type: Any.Type, plans: ValueHashPlans) -> Root {
        let framework = FrameworkModules.declares(type)
        let besideTimelines = framework && type is any _PlainMemoizedBesideTimelines.Type
        let excluded = framework && !besideTimelines && !(type is any _PlainMemoizedFrameworkView.Type)
        let made = Root(comparison: excluded ? nil : plans.comparison(for: type), onlyBesideTimelines: besideTimelines)
        roots[ObjectIdentifier(type)] = made
        return made
    }
}

/// A view of the framework's own that the plain memo takes as it takes an app's:
/// ``FrameworkModules`` keeps the framework's composites out, and this lets one
/// back in.
///
/// For a view whose drawing is the app's own work, dear, and a function of what
/// the memo already watches: its fields, the environment it is drawn under, and
/// what its deferred closure reads (observed at its identity). A `Canvas` is the
/// one: its renderer is the app's, and a `Canvas` drawn beside a `TimelineView`
/// ran it on every frame of the timeline, because the timeline's entry drops the
/// timeline's ancestors and nothing below them kept the canvas (tuiarcade's
/// feedback, 2026-11-17: 7 ms of a 16.7 ms frame for a canvas that never
/// changed). SwiftUI runs only the timeline's content on a tick. Kept here, the
/// canvas is a sibling of the timeline and survives its clear, and its renderer,
/// a closure, is passed over in the comparison as an app's view's is, by the
/// same argument: nothing above it wrote, so its parent built the same one.
///
/// Not for a view whose drawing reads what no key sees — a hover, a style's
/// configuration, the focus — which is why the framework's composites stay out.
package protocol _PlainMemoizedFrameworkView {}

/// A control of the framework's own that the plain memo takes as it takes an
/// app's view while a `TimelineView` is live, and only then: a `List`, a
/// `Button`.
///
/// No buffer above a live timeline can be kept (its draw asks for the wake of
/// its next entry), so at every entry the walk goes down from the app's root
/// to the timeline, and draws again every framework composite it passes that
/// has no memo of its own. The app's composites are served there, or walked
/// from the body they kept (``FrameBodyKeep``), but a control beside the
/// timeline drew itself whole: a `List` listed and laid out its rows, and a
/// `Button` resolved its style and drew its label, at every entry, their
/// rows' and labels' content served from their own memos (tuiarcade's
/// TUI-FEEDBACK.md, M2 item 3). SwiftUI runs only the timeline's content.
///
/// The control's memo is the one an app's view gets, with its journal, its
/// leases, its store gates and its invalidations, so it is as safe as the
/// app's memo above it, which stores the same subtree whenever nothing beside
/// the control declines: the control's value and the environment it is drawn
/// under are keyed; its `@State` and its handler's drawn state invalidate;
/// a `Binding` it reads is observed by the kept render; and a control that
/// holds the focus declines to be stored, as it does inside the app's memo.
/// Outside a live timeline the app's memo above decides for the whole, as it
/// always has, and the control pays for no key.
package protocol _PlainMemoizedBesideTimelines {}

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
    let renderedBefore = unsafe cache.rowWork.rendered
    let buffer = renderValueMemoized(
        key: PlainKey(
            view: view, comparison: comparison, plans: plans,
            stamp: cache.revalidation.stamps.stamp(of: context.environment)),
        viewType: V.self, context: context, slot: plainMemoSlot,
        build: { PlainRow(view: view, comparison: comparison, plans: plans) },
        render: { render($0.view, $1) })
    unsafe memo.noteDrawn(at: hash, served: cache.rowWork.rendered == renderedBefore, measuring: context.isMeasuring)
    return buffer
}

/// `measureChild`'s composite branch, through the memo.
@inline(never)
@MainActor
func measurePlainMemoized<V: View>(
    _ view: V, comparison: ValueComparison, proposal: ProposedViewSize, context: RenderContext,
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
