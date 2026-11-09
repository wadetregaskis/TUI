//  🖥️ TUI — A Terminal UI framework for Swift
//  BodyKeep.swift
//
//  A stack measures a composite and then draws it, and each ran its `body`: a
//  body that takes 50 ms took 100 ms a frame. What the measure evaluated is kept
//  for the pass here, and a draw of the same view value under an environment it
//  could not tell from the measure's takes it. A nest of composites holding fresh
//  arrays ran 2, 3 and 4 bodies by depth, since each new address missed the measure
//  memo: now 1, 1 and 1. `TUI_KEEP_BODIES=0` turns it off, to compare.
//
//  Only a body seen to take real time: keeping one costs a hash, an allocation, a
//  table and a look at the environment, more than most bodies, which only build a
//  few values (+28% of `session/notes` keeping them all). So measures are timed, on
//  a sample, and a type seen over the line is kept from then on, unless its draws
//  seldom take what is kept, when it rests for a while (`judgeKeeps`).
//
//  Nothing but the body is kept, and only until the walk ends. No buffer: see
//  `render-memo-store-rules`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

/// A property that reads something the walk itself is still deciding, so that an
/// evaluation at a measure and one at the draw after it can differ: which control
/// has the focus is settled by the registrations the draw makes.
package protocol _DecidedDuringTheWalk {}

/// The bodies this walk's measures evaluated, for the draw that follows. Main-actor
/// only, as the cache's tables are.
package final class BodyKeep {
    /// Whether bodies are kept under this cache. A test sets it per cache.
    package var isOn = BodyKeep.isOnByDefault

    private static let isOnByDefault = ProcessInfo.processInfo.environment["TUI_KEEP_BODIES"] != "0"

    private struct Key: Hashable {
        let identityHash: Int
        let viewType: ObjectIdentifier
        let valueHash: Int
    }

    /// One allocation for the view and its body together. The view is held so that
    /// an address in its bytes cannot come back for another value while the entry
    /// stands: the value hash reads addresses.
    private final class Box<V: View> {
        let view: V
        let body: V.Body

        init(view: V, body: V.Body) {
            self.view = view
            self.body = body
        }
    }

    private struct Kept {
        let box: AnyObject
        let lease: ObservationLease?
        let environment: EnvironmentValues
    }

    /// Whether every body is kept, however quick, rather than waiting to see one take
    /// the time: what a test sets, and `TUI_KEEP_BODIES=all`, so that whether a test
    /// runs through this does not depend on how loaded its machine is.
    package var keepsEveryBody = BodyKeep.keepsEveryBodyByDefault

    private static let keepsEveryBodyByDefault = ProcessInfo.processInfo.environment["TUI_KEEP_BODIES"] == "all"

    /// How long a body has to be seen to take for its type to be kept.
    private static let slowBody = Duration.microseconds(20)

    /// The types seen to take it: only ever added to, so at most one per type.
    private var slowTypes: Set<ObjectIdentifier> = []

    /// Which measures are timed.
    private var sampler = TimingSampler()

    /// Whether a body's time is read at all: see ``RenderCache/learnsFromTiming``.
    package var learnsFromTiming: Bool {
        get { sampler.isOn }
        set { sampler.isOn = newValue }
    }

    private var table: [Key: Kept] = [:]

    /// Whether nothing is kept: what a test asks, between walks.
    package var isEmpty: Bool { table.isEmpty }
    /// How many bodies are kept, for a census of the caches (`Stress --cache-sizes`).
    package var count: Int { table.count }
    private var verdicts: [ObjectIdentifier: Verdict] = [:]

    /// What it has done: what the tests read.
    package struct Counts: Equatable {
        package var kept = 0
        package var taken = 0
        package var environmentMisses = 0
    }
    package var counts = Counts()

    /// The passes begun: what a type's cooldown is counted in.
    private var pass = 0

    /// What each slow type kept and had taken this pass: the bodies a draw took
    /// against the different ones a measure kept.
    private var tally: [ObjectIdentifier: (kept: Int, taken: Int)] = [:]

    /// What each type whose keeps go untaken has come to.
    private var gates: [ObjectIdentifier: Gate] = [:]

    private struct Gate {
        /// Passes running in which too few of its bodies were taken.
        var strikes = 0
        /// The pass until which its bodies are not kept.
        var until = 0
    }

    /// A slow type stops being kept when fewer than one in this many of the bodies
    /// a pass keeps for it are taken. A keep and a take that misses cost about 0.8 µs
    /// together (`gradients`: 2.7% of a 23 ms frame over 812 keeps), and a body is
    /// kept only once seen to take 20 µs, so a keep pays for itself once 1 in 25 is
    /// taken. A draw's environment can differ from its measure's every time, as it
    /// does for `gradients`' rows (1 taken in 200), or a draw never ask, as for
    /// `stateful`'s (none in 50 a pass).
    private static let takenAtLeastOneIn = 16

    package init() {}

    /// Lets go of what is kept. Between walks too: a walk made again reads what the
    /// walk before it wrote. The table holds environments, which hold the cache.
    func reset() {
        if !table.isEmpty { table.removeAll(keepingCapacity: true) }
    }

    /// Starts a pass.
    func beginPass() {
        reset()
        sampler.beginPass()
        pass &+= 1
        if !tally.isEmpty { judgeKeeps() }
    }

    /// Cools each type whose keeps went untaken two passes running, for 4, 8 … at
    /// most 64 passes, as the plain memo's gate does (``PlainMemo``); one whose keeps
    /// are taken is forgotten.
    private func judgeKeeps() {
        for (type, counted) in tally {
            guard counted.taken * Self.takenAtLeastOneIn < counted.kept else {
                gates[type] = nil
                continue
            }
            var gate = gates[type] ?? Gate()
            gate.strikes += 1
            if gate.strikes >= 2 { gate.until = pass + min(64, 1 << min(gate.strikes, 6)) }
            gates[type] = gate
        }
        tally.removeAll(keepingCapacity: true)
    }

    /// Whether a composite of `V` is one to keep: seen to be slow, or a test says so.
    @inline(__always)
    func isSlow<V: View>(_: V.Type) -> Bool {
        guard isOn else { return false }
        if keepsEveryBody { return true }
        let type = ObjectIdentifier(V.self)
        guard !slowTypes.isEmpty, slowTypes.contains(type) else { return false }
        guard !gates.isEmpty, let gate = gates[type] else { return true }
        return gate.until <= pass
    }

    /// The instant to time this measure's evaluation from, if it is timed.
    @inline(__always)
    func startTiming() -> ContinuousClock.Instant? {
        guard isOn else { return nil }
        return sampler.startTiming()
    }

    /// Notes how long an evaluation of a `V` took, since ``startTiming()``.
    @inline(__always)
    func noteEvaluation<V: View>(of _: V.Type, since start: ContinuousClock.Instant?) {
        guard let start, ContinuousClock.now - start >= Self.slowBody else { return }
        slowTypes.insert(ObjectIdentifier(V.self))
    }

    /// Whether anything is kept: nothing to look for if not.
    var hasKept: Bool { !table.isEmpty }

    /// Whether a composite of `V` may be kept: an app's own (a framework view's body
    /// forwards, and costs less than keeping it, by up to 25% of a frame of `menus`),
    /// and not one that holds something a draw prepares differently from a measure (a
    /// class property, whose place moves only for a draw) or whose properties read
    /// what the walk is deciding as it goes (``_DecidedDuringTheWalk``).
    ///
    /// The type is asked once. The probes a plan keeps say of a value that it holds no
    /// such object, which is most views holding a model, whose declared class might
    /// have had a subclass that was a property.
    @inline(__always)
    @MainActor
    func mayKeep<V: View>(_ view: V, plan: SlotPlan?) -> Bool {
        guard isOn else { return false }
        switch verdicts[ObjectIdentifier(V.self)] ?? decide(V.self, plan: plan) {
        case .never: return false
        case .always: return true
        case .ifProbesFindNothing: return plan?.probes.map { !probesFindSomething(in: view, $0) } ?? false
        }
    }

    private enum Verdict {
        case never
        case always
        case ifProbesFindNothing
    }

    @inline(never)
    @MainActor
    private func decide(_ type: Any.Type, plan: SlotPlan?) -> Verdict {
        let made: Verdict
        if FrameworkModules.declares(type) || Self.readsTheWalk(type) {
            made = .never
        } else if let plan {
            made = !plan.mayHoldObjects ? .always : plan.probes == nil ? .never : .ifProbesFindNothing
        } else {
            made = .always
        }
        verdicts[ObjectIdentifier(type)] = made
        return made
    }

    private static func readsTheWalk(_ type: Any.Type) -> Bool {
        if type is any _DecidedDuringTheWalk.Type { return true }
        if type is any DynamicProperty.Type { return !(type is any _BoundFromTheWalk.Type || type is any _ComparedOpaquely.Type) }
        guard RuntimeFields.Kind(of: type) == .struct else { return false }
        return RuntimeFields.fields(of: type).contains { readsTheWalk($0.type) }
    }

    @MainActor
    private func key<V: View>(_ view: V, context: RenderContext, cache: RenderCache) -> Key? {
        guard let valueHash = viewValueHash(view, plans: cache.valueHashPlans) else { return nil }
        return Key(
            identityHash: measureIdentityHash(context.identity, generation: context.measureGeneration),
            viewType: ObjectIdentifier(V.self), valueHash: valueHash)
    }

    /// What this walk evaluated for `view` at this identity, if its environment is
    /// one a body could not tell from this one.
    ///
    /// The environment has to be asked: a measure's is not a draw's (`\.isFocused`,
    /// a stack's axis, a scroll view's window), and trusting it, as the per-pass
    /// measure memo may for a size, failed 11 tests.
    @MainActor
    func take<V: View>(_ view: V, context: RenderContext, cache: RenderCache) -> V.Body? {
        guard !table.isEmpty, let key = key(view, context: context, cache: cache), let kept = table[key] else {
            return nil
        }
        if kept.environment.storageWord != context.environment.storageWord {
            let stamps = cache.revalidation.stamps
            guard let old = stamps.stamp(of: kept.environment), let new = stamps.stamp(of: context.environment),
                old === new || old.isEquivalent(to: new)
            else {
                counts.environmentMisses += 1
                return nil
            }
        }
        counts.taken += 1
        if !keepsEveryBody { tally[ObjectIdentifier(V.self), default: (0, 0)].taken += 1 }
        cache.leases.use(kept.lease)
        return unsafe unsafeDowncast(kept.box, to: Box<V>.self).body
    }

    /// Keeps what a measure of `view` evaluated.
    @MainActor
    func keep<V: View>(_ body: V.Body, of view: V, lease: ObservationLease?, context: RenderContext, cache: RenderCache) {
        guard let key = key(view, context: context, cache: cache) else { return }
        counts.kept += 1
        let replaced = table.updateValue(
            Kept(box: Box(view: view, body: body), lease: lease, environment: context.environment), forKey: key)
        // A body kept again under the same key is one a draw could take, once.
        if replaced == nil, !keepsEveryBody { tally[ObjectIdentifier(V.self), default: (0, 0)].kept += 1 }
    }
}

extension SlotPlan {
    /// Whether a value of the planned type may hold a property object, or something
    /// only its value can say about.
    var mayHoldObjects: Bool {
        switch action {
        case .none, .leaf: false
        case .fields(let fields): fields.steps.contains { $0.slot.mayHoldObjects }
        case .optional(let optional): optional.wrapped.mayHoldObjects
        case .enumeration, .existential, .object, .dynamicClass: true
        }
    }
}

extension RenderCache {
    /// Lets go of what only a pass's end lets go of, for a walk that no pass's end
    /// follows (`ViewRenderer`'s snapshot): an environment kept here holds the
    /// cache, and the snapshot's context would never be freed.
    package func endOneOffWalk() {
        bodyKeep.reset()
        revalidation.endPass()
    }
}
