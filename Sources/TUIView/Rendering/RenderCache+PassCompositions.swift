//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+PassCompositions.swift
//
//  What a layout composes from its content, made once a pass at its place and
//  served to the measures and the draw after it: a `Form` reads its content
//  into rows and measures every one of them to find its label column and its
//  width before it can lay out a column, and was asked for that column three
//  times a frame — two measures and the draw — each reading and measuring
//  every row again, and each a fresh set of values for the measure memo to
//  store and keep.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// A place a layout composed something this pass: its identity, hashed as the
/// measure memo hashes it (the measure generation folded in, so a composition
/// made under one generation is never served under another), and the width
/// it was laid out at.
struct PassCompositionKey: Hashable {
    let identityHash: Int
    let availableWidth: Int
}

/// What ``RenderCache/composedOncePerPass(for:context:_:)`` keeps at a place.
struct PassComposition {
    /// The type and the value hash of the view the composition was made from.
    let viewType: ObjectIdentifier
    let valueHash: Int
    /// The view itself, kept so that no address its hash read can be handed
    /// to another value while the entry stands, as the measure memo keeps the
    /// values it stores sizes for (`measuredValues`).
    let view: Any
    /// The environment it was made under.
    let environment: EnvironmentStamp
    /// What the making observed, which a computation it is served to holds.
    let lease: ObservationLease?
    let composed: AnyObject
}

extension RenderCache {
    /// `make()`'s result for `view` at `context`'s place, made once a pass and
    /// served again while the pass lasts to the same value laid out at the same
    /// width under an environment it cannot tell from the one it was made under.
    ///
    /// For a layout that composes its content before it can measure or draw
    /// it, and is asked to do both more than once a pass: `make()` reads only
    /// `view` and `context`'s identity, environment and width, never whether
    /// the context measures or draws, nor its height. Under the conditions the
    /// measure memo keeps a size under, and no others: a pass's volatile-read
    /// tracker installed (none beneath a probe), the view's value hashable,
    /// the environment comparable, and nothing volatile read while it is made.
    /// The environment has to be compared, not trusted: a measure's is not a
    /// draw's (``BodyKeep/take(_:context:cache:)``).
    @MainActor
    package func composedOncePerPass<V: View, Composed: AnyObject>(
        for view: V, context: RenderContext, _ make: () -> Composed
    ) -> Composed {
        guard let tracker = volatileReadTracker, let valueHash = viewValueHash(view, plans: valueHashPlans),
            let environment = revalidation.stamps.stamp(of: context.environment)
        else { return make() }
        let key = PassCompositionKey(
            identityHash: measureIdentityHash(context.identity, generation: context.measureGeneration),
            availableWidth: context.availableWidth)
        if let kept = passCompositions[key], kept.viewType == ObjectIdentifier(V.self), kept.valueHash == valueHash,
            kept.environment === environment || kept.environment.isEquivalent(to: environment),
            let composed = kept.composed as? Composed
        {
            compositionCounts.served += 1
            leases.use(kept.lease)
            return composed
        }
        let unsafeBefore = tracker.cacheUnsafeCount
        let mark = leases.beginComputation()
        let composed = make()
        let lease = leases.endComputation(mark)
        if tracker.cacheUnsafeCount == unsafeBefore {
            compositionCounts.kept += 1
            passCompositions[key] = PassComposition(
                viewType: ObjectIdentifier(V.self), valueHash: valueHash, view: view, environment: environment,
                lease: lease, composed: composed)
        }
        return composed
    }

    /// Lets go of every composition kept this pass.
    func forgetPassCompositions() {
        if !passCompositions.isEmpty { passCompositions.removeAll(keepingCapacity: true) }
    }

    /// Lets go of the compositions kept at one place, whatever width: what
    /// ``forgetSizes(of:measureGeneration:)`` forgets with its sizes.
    func forgetPassCompositions(atIdentityHash identityHash: Int) {
        guard !passCompositions.isEmpty else { return }
        let stale = passCompositions.keys.filter { $0.identityHash == identityHash }
        for key in stale { passCompositions.removeValue(forKey: key) }
    }
}
