//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderCache+EnvironmentSlots.swift
//
//  The render cache's record of what each environment modifier applied, and
//  the change it reports — the check that keeps a scoped style change from
//  serving a buffer drawn under the old style — and its twin for the type of
//  content each `AnyView` erases.
//
//  Split out of `RenderCache.swift`, which had reached the file-length ceiling.
//  The table itself stays a stored property there, as a class's must.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

extension RenderCache {
    /// What ``noteAppliedEnvironment(_:identity:keyPath:depth:)`` found.
    public enum EnvironmentChange {
        /// Nothing was applied here before — nothing below can be stale. True
        /// because a slot is kept for as long as anything cached below it is:
        /// seen this pass, or inside a subtree a memo served (see
        /// ``removeInactive()``).
        case first
        /// The same value as last pass.
        case unchanged
        /// A different value: cached buffers below are stale.
        case changed
        /// The value is not `Equatable`, so change cannot be detected at all.
        case incomparable
    }

    /// What one slot applied last, and when.
    struct AppliedEnvironment {
        var value: Any
        var lastSeenFrame: UInt64
        var isComparable: Bool
    }

    /// Records the environment value applied at a slot and reports whether it
    /// differs from the previous pass.
    ///
    /// This is what keeps a *scoped* style change from serving a stale buffer.
    /// The cache key is the identity's hash + view value + size, and deliberately carries
    /// no environment: a `.foregroundStyle` applied **above** an `.equatable()`
    /// boundary leaves the view value untouched, so without this the lookup hits
    /// and returns the buffer rendered under the old style. Detecting the change
    /// where it is applied — rather than fingerprinting the environment at every
    /// lookup — costs one comparison per environment modifier per pass instead
    /// of a dictionary walk per memoized view per pass.
    ///
    /// Called from both the measure and render walks. That is deliberate, and it
    /// is *not* the measure-side-effect bug: this table is the cache's own
    /// coherency record, not view state. The measure memo has the same blind
    /// spot as the buffer cache and measurement runs first, so a change noticed
    /// only on the render walk would already have served a stale size. Whichever
    /// walk sees it first clears; the other then reports `.unchanged`, so the
    /// clear happens once.
    ///
    /// - Parameter value: The value applied. An autoclosure, evaluated at most
    ///   once and only where it is used — a slot met for the first time, or
    ///   the first visit of a pass to a slot that can still be compared — so
    ///   a repeat visit pays nothing to make it. What a caller makes is not
    ///   always free: `EnvironmentModifier` casts its value to `any Palette`
    ///   and boxes it in an `Any` (an allocation for anything over three
    ///   words, as most style values are), and two-pass layout visits each
    ///   modifier several times a frame.
    /// - Returns: `.incomparable` when `value` is not `Equatable`, or is a
    ///   ``PartiallyComparable`` wrapper around a value that is not — the
    ///   caller must then decline caching, because nothing here can tell
    ///   whether it changed.
    public func noteAppliedEnvironment(
        _ value: @autoclosure () -> Any,
        identity: ViewIdentity,
        keyPath: AnyKeyPath,
        depth: Int
    ) -> EnvironmentChange {
        let slot = EnvironmentSlot(identity: identity, keyPath: keyPath, depth: depth)
        guard var previous = appliedEnvironment[slot] else {
            let value = value()
            let comparable = Self.canCompare(value)
            appliedEnvironment[slot] = AppliedEnvironment(
                value: value, lastSeenFrame: frameCounter, isComparable: comparable)
            return comparable ? .first : .incomparable
        }

        // Already answered this pass. Two-pass layout visits the same modifier
        // many times per frame and the value cannot change between those visits,
        // so everything below — making the value, two existential casts and a
        // comparison, on a path every environment modifier in the tree runs
        // through — is done once per pass rather than once per visit. Without
        // this the whole scheme costs ~17% of a frame; with it, nothing
        // measurable.
        if previous.lastSeenFrame == frameCounter {
            return previous.isComparable ? .unchanged : .incomparable
        }

        // A slot that went incomparable stays so, and never needs the value.
        let current: Any? = previous.isComparable ? value() : nil
        guard let current, let equatable = current as? any Equatable else {
            previous.lastSeenFrame = frameCounter
            previous.isComparable = false
            appliedEnvironment[slot] = previous
            return .incomparable
        }
        if equatable.isEqual(to: previous.value) {
            previous.lastSeenFrame = frameCounter
            appliedEnvironment[slot] = previous
            return .unchanged
        }
        // Unequal — or a wrapper that has come to hold what it cannot compare,
        // which answers unequal to everything. Asked only here, past the
        // comparison, so an unchanged slot pays nothing for it. The slot goes
        // incomparable as a raw value's does; and what is cached below was
        // drawn under the value before, which did differ, so it goes too.
        if let partial = current as? any PartiallyComparable, !partial.isComparable {
            previous.lastSeenFrame = frameCounter
            previous.isComparable = false
            appliedEnvironment[slot] = previous
            clearAffected(by: identity)
            return .incomparable
        }
        appliedEnvironment[slot] = AppliedEnvironment(
            value: current, lastSeenFrame: frameCounter, isComparable: true)
        return .changed
    }

    /// Whether a slot can compare `value` from pass to pass: `Equatable`, and
    /// not a ``PartiallyComparable`` wrapper around a value that is not. Asked
    /// once, when a slot is first met.
    private static func canCompare(_ value: Any) -> Bool {
        guard value is any Equatable else { return false }
        return (value as? any PartiallyComparable)?.isComparable ?? true
    }

    /// What an `AnyView` last held at one identity and depth — see
    /// ``noteErasedContent(_:identity:depth:)``.
    struct ErasedContent {
        var type: ObjectIdentifier
        var lastSeenFrame: UInt64
        let identity: ViewIdentity
    }

    /// Records the TYPE of what an `AnyView` erases, and reports whether it is
    /// a different type from the one it held last pass.
    ///
    /// An `AnyView` draws its content at its own identity, and so does every
    /// modifier inside it, so swapping the content for one of another type — a
    /// modifier added or removed by a type-erased conditional — leaves every
    /// memo below at the identity it had, keyed by a value that did not change.
    /// Unnoticed, it served what it had drawn under the modifier that had gone.
    /// The caller clears the subtree on `true`, as an environment modifier
    /// does on `.changed`.
    ///
    /// Its own table, not ``noteAppliedEnvironment(_:identity:keyPath:depth:)``,
    /// because an `AnyView` is visited far more often than an environment
    /// modifier — every framework control that erases its label has one, and a
    /// measure cascade visits each many times — and a slot's key hashes an
    /// `AnyKeyPath` on every visit, where this one is two integers. Once per
    /// pass, like the environment's; kept and swept by the same liveness rule
    /// (``removeInactive()``).
    ///
    /// - Parameters:
    ///   - type: The erased content's dynamic type.
    ///   - identity: The `AnyView`'s identity.
    ///   - depth: `RenderContext.environmentApplicationDepth` there, which
    ///     tells apart two `AnyView`s nested at one identity.
    /// - Returns: Whether the type changed since the last pass.
    package func noteErasedContent(_ type: ObjectIdentifier, identity: ViewIdentity, depth: Int) -> Bool {
        let key = finalizeHashWord(
            mixHashWord(
                mixHashWord(hashFoldSeed, UInt64(bitPattern: Int64(identity.structuralHash))),
                UInt64(bitPattern: Int64(depth))))
        guard let index = erasedContent.index(forKey: key) else {
            erasedContent[key] = ErasedContent(type: type, lastSeenFrame: frameCounter, identity: identity)
            return false
        }
        if erasedContent.values[index].lastSeenFrame == frameCounter { return false }
        erasedContent.values[index].lastSeenFrame = frameCounter
        guard erasedContent.values[index].type != type else { return false }
        erasedContent.values[index].type = type
        return true
    }
}
