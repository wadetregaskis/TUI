//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RenderCache+Revalidation.swift
//
//  What a render cache keeps to re-check a row instead of dropping it.
//
//  Option C serves a memoized row after a parent's write when the row's
//  rebuilt value and its environment compare equal to what it was drawn
//  from. Everything the cache keeps for that lives in one object, held in one
//  stored property of the cache, so each piece added is a field here and not
//  another stored property on a class already at its file's length ceiling.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

/// The cache's state for re-checking rows.
///
/// A class held by a `let`: reading a field reaches it through a pointer the
/// cache never reassigns. Main-actor only, as the cache's tables are.
package final class RevalidationState {
    /// What each row type can hold, walked once per type: whether a row of it
    /// can be re-checked by its value at all. See ``TypeWalk``.
    package var typeWalk = TypeWalk()

    /// The environments rows were drawn under, as compared: what tells
    /// whether a row would be drawn differently under the environment it
    /// would get now. See ``EnvironmentStamp``.
    package let stamps = EnvironmentStamps()

    /// Whether every value-memo store stamps the environment it was drawn
    /// under, so the stamps' counts say which keys would keep rows from being
    /// re-checked (`Stress --census`). Off, nothing is stamped: no store does
    /// so until Option C's re-check needs it (C4b).
    package var countsStamps = false

    /// What the soft drain and the lookups have done, for the census and
    /// the tests.
    package var counts = Counts()

    /// See ``counts``.
    package struct Counts: Equatable {
        /// Stores that recorded what they were drawn from and under.
        package var stamped = 0
        /// Entries a soft drain kept, marked suspect.
        package var suspectsMarked = 0
        /// Entries a soft drain dropped below a soft writer, because they
        /// recorded nothing to re-check them by.
        package var unstampedDropped = 0
        /// Suspects dropped when they were looked up without being re-checked.
        package var suspectsDropped = 0
        /// Suspects re-checked and found unchanged: served (C4c).
        package var rechecked = 0
        /// Suspects whose rebuilt value differed from what they were drawn from.
        package var unequalValues = 0
        /// Suspects whose environment, or modifier depth, differed.
        package var unequalEnvironments = 0
    }

    /// Whether a suspect is re-checked and served when it is unchanged (C4c),
    /// rather than dropped as a hard drain would have dropped it. On, now
    /// that every framework environment class has a decision
    /// (`EnvironmentClassAuditTests`); `TUIKIT_OPTION_C=0` turns it off, to
    /// compare a frame drawn without it.
    package var servesRechecked = RevalidationState.servesRecheckedByDefault

    /// Why re-checks found environments unequal, by the first key that
    /// differed — or `depth` and `uncomparable` — when ``countsStamps`` is on
    /// (the census): what to make neutral, project or audit next.
    package private(set) var unequalEnvironmentReasons: [String: Int] = [:]

    func noteUnequalEnvironment(_ reason: @autoclosure () -> String) {
        guard countsStamps else { return }
        unequalEnvironmentReasons[reason(), default: 0] += 1
    }

    private static let servesRecheckedByDefault =
        ProcessInfo.processInfo.environment["TUIKIT_OPTION_C"] != "0"

    /// The passes begun: what a cooldown is counted in.
    private var pass = 0

    /// Rows whose value keeps changing, by identity hash (Option C, C5): how
    /// many re-checks in a row found the value unequal, and the pass until
    /// which the row is neither recorded nor re-checked. A row that changes
    /// every frame — a churning list — was rebuilt to be compared, found
    /// unequal, and drawn anyway, every frame: +25% on `churn`.
    private var cooldowns: [Int: (run: Int, until: Int)] = [:]

    /// Starts a pass: this pass's stamps, and the cooldowns that have run out.
    package func beginPass() {
        pass &+= 1
        stamps.beginPass()
        if pass.isMultiple(of: 64), !cooldowns.isEmpty { cooldowns = cooldowns.filter { $0.value.until >= pass - 64 } }
    }

    /// Ends a pass: this pass's stamps, and the environments they were
    /// memoized by, are let go (``EnvironmentStamps/endPass()``).
    package func endPass() {
        stamps.endPass()
    }

    /// Whether the row at `identityHash` is cooling down: its stores record
    /// nothing, so a parent's write drops it, unchecked, as it did before.
    package func isCoolingDown(_ identityHash: Int) -> Bool {
        guard !cooldowns.isEmpty, let cooldown = cooldowns[identityHash] else { return false }
        return cooldown.until > pass
    }

    /// Notes a re-check's verdict at `identityHash`: an unequal value extends
    /// the row's run — from the second, a cooldown of 2, 4, 8 … at most 64
    /// passes — and an equal one ends it.
    package func noteVerdict(_ verdict: RecheckVerdict, at identityHash: Int) {
        switch verdict {
        case .unchanged:
            if !cooldowns.isEmpty { cooldowns[identityHash] = nil }
        case .valueChanged:
            let run = (cooldowns[identityHash]?.run ?? 0) + 1
            let until = run >= 2 ? pass + min(64, 1 << min(run - 1, 6)) : pass
            cooldowns[identityHash] = (run, until)
        case .environmentChanged, .off:
            break
        }
    }

    /// What ``eligibility(ofRowsOf:)`` has answered, by type.
    private var eligibilities: [ObjectIdentifier: RowEligibility] = [:]

    /// The `==` of each eligible row type, made once from its metatype: what
    /// a record compares its snapshot by, so a store casts nothing.
    private var equalities: [ObjectIdentifier: (Any, Any) -> Bool] = [:]
    private var lastEqualityType: ObjectIdentifier?
    private var lastEquality: ((Any, Any) -> Bool)?

    package init() {}

    /// Whether a memoized row whose built view is of `type` can be re-checked
    /// by its value, rather than drawn again, when a parent writes (Option C,
    /// §5.2): its view must be `Equatable` — the re-check is its `==` — and
    /// hold nothing the type walk refuses: a `Binding`, whose value its own
    /// bytes do not say; an existential, which a hand-written `==` over it
    /// cannot see all of; or a type the runtime cannot describe. Decided once
    /// per type.
    package func eligibility(ofRowsOf type: Any.Type) -> RowEligibility {
        if let known = eligibilities[ObjectIdentifier(type)] { return known }
        let decided: RowEligibility
        if !(type is any Equatable.Type) {
            decided = .notEquatable
        } else if let refusal = typeWalk.verdict(for: type).refusal {
            decided = .refused(refusal)
        } else {
            decided = .eligible
        }
        eligibilities[ObjectIdentifier(type)] = decided
        return decided
    }

    /// The `==` rows of `type` are compared by, when they can be re-checked
    /// (``eligibility(ofRowsOf:)``); `nil` when they cannot. Made once per
    /// type, by opening its metatype — not by casting each row to
    /// `any Equatable` as it is stored, which cost a dynamic cast per store
    /// (3.9% of a `scrollfollow` frame).
    package func equality(ofRowsOf type: Any.Type) -> ((Any, Any) -> Bool)? {
        let id = ObjectIdentifier(type)
        // The last type asked first: a list stores rows of one type in a run.
        if id == lastEqualityType { return lastEquality }
        defer { lastEqualityType = id }
        if let known = equalities[id] {
            lastEquality = known
            return known
        }
        lastEquality = nil
        guard eligibility(ofRowsOf: type) == .eligible, let equatable = type as? any Equatable.Type else { return nil }
        func make<E: Equatable>(_: E.Type) -> (Any, Any) -> Bool {
            { lhs, rhs in
                guard let left = lhs as? E, let right = rhs as? E else { return false }
                return left == right
            }
        }
        let equal = make(equatable)
        equalities[id] = equal
        lastEquality = equal
        return equal
    }
}

/// What a re-check found.
package enum RecheckVerdict {
    /// The row and its environment are what it was drawn from and under.
    case unchanged
    /// The rebuilt row differs.
    case valueChanged
    /// The environment, or the modifier depth above it, differs.
    case environmentChanged
    /// Serving re-checked rows is off; nothing was compared.
    case off
}

/// Whether rows of a type can be re-checked by their value: see
/// ``RevalidationState/eligibility(ofRowsOf:)``.
package enum RowEligibility: Equatable, Sendable {
    /// They can.
    case eligible
    /// The row's view is not `Equatable`: there is no `==` to re-check it by.
    case notEquatable
    /// The type walk refused it, and why.
    case refused(TypeWalk.Refusal)
}

// MARK: - What an entry is re-checked by

extension RenderCache {
    /// What a memoized subtree was drawn from and under, kept with its entry
    /// so a parent's write can re-check it rather than drop it (Option C,
    /// §2.4).
    ///
    /// A class: an entry holds it by one reference, which the drain and the
    /// lookups read without copying an existential and a stamp each time.
    package final class Revalidation {
        /// The row's view value as it was built when drawn — or, after a
        /// re-check found it unchanged, as rebuilt then: what the rebuilt value
        /// is compared with, by ``equal``. Replaced on an equal verdict, so it
        /// holds the row's current captures, which the live model holds anyway,
        /// and not those of the render that drew it (v4 §2.4).
        package var snapshot: Any
        /// The `==` of the snapshot's type.
        package let equal: (Any, Any) -> Bool
        /// The environment it was drawn under (``EnvironmentStamp``), from the
        /// context the memo was handed.
        package var environment: EnvironmentStamp
        /// How many environment modifiers that note themselves were above it.
        package let depth: Int

        init(snapshot: Any, equal: @escaping (Any, Any) -> Bool, environment: EnvironmentStamp, depth: Int) {
            self.snapshot = snapshot
            self.equal = equal
            self.environment = environment
            self.depth = depth
        }
    }

    /// The record for a row of `row`'s value drawn under `context`, or `nil`
    /// when it cannot be re-checked: its view is not eligible
    /// (``RevalidationState/eligibility(ofRowsOf:)``), or its environment
    /// cannot be compared. An entry stored with `nil` is dropped by a soft
    /// drain, as every entry below a writer is today.
    package func revalidationRecord<Row>(for row: Row, context: RenderContext) -> Revalidation? {
        guard let equal = revalidation.equality(ofRowsOf: Row.self),
            !revalidation.isCoolingDown(context.identity.structuralHash),
            let stamp = revalidation.stamps.stamp(of: context.environment)
        else { return nil }
        revalidation.counts.stamped += 1
        return Revalidation(snapshot: row, equal: equal, environment: stamp, depth: context.environmentApplicationDepth)
    }
}

// MARK: - Re-checking a suspect

extension RenderCache {
    /// The value memo's re-check of a suspect, `record`: the row rebuilt
    /// (`build`) and compared by its `==` with the snapshot; the environment
    /// it would be drawn under now, by its stamp; and the depth of
    /// environment modifiers above it. On an equal verdict the record takes
    /// the rebuilt row and the current stamp. `false` without a look when
    /// serving re-checked rows is off (``RevalidationState/servesRechecked``).
    ///
    /// The lookup is handed the memo's own `build` and environment and makes
    /// the closure that calls this only for a suspect: a lookup that finds
    /// none — 4,000 a frame on `fanout` — makes nothing. A re-check closure
    /// made for every lookup cost that scenario 19% (stored, capturing the
    /// render context) and `anyview` 4% (on the stack).
    package func recheckRow<Row>(
        _ record: Revalidation, rebuild build: () -> Row, environment: EnvironmentValues, depth: Int
    ) -> RecheckVerdict {
        guard revalidation.servesRechecked else { return .off }
        let row = build()
        guard record.equal(record.snapshot, row) else {
            revalidation.counts.unequalValues += 1
            return .valueChanged
        }
        guard record.depth == depth,
            let stamp = revalidation.stamps.stamp(of: environment),
            stamp === record.environment || stamp.isEquivalent(to: record.environment)
        else {
            revalidation.counts.unequalEnvironments += 1
            revalidation.noteUnequalEnvironment(
                record.depth != depth
                    ? "depth \(record.depth) → \(depth)"
                    : revalidation.stamps.stamp(of: environment)
                        .flatMap { $0.firstDifference(from: record.environment) }
                        .map(EnvironmentStamps.debugName(of:)) ?? "uncomparable now")
            return .environmentChanged
        }
        record.snapshot = row
        record.environment = stamp
        return .unchanged
    }

    /// What a lookup does with `entry`, a suspect: re-checked by `recheck`
    /// and, unchanged, unmarked and `true` — the lookup goes on to its usual
    /// checks; otherwise dropped and `false`. Dropped DIRECTLY, not through
    /// a clear: ``Stats/subtreeClears`` does not move, so the memo around it
    /// still stores what it draws (`renderValueMemoized`'s
    /// `invalidatedDuringRender`).
    func resolveSuspect(_ entry: CacheEntry, recheck: (Revalidation) -> RecheckVerdict, drop: () -> Void) -> Bool {
        let verdict = entry.revalidation.map(recheck) ?? .off
        revalidation.noteVerdict(verdict, at: entry.identity.structuralHash)
        guard verdict == .unchanged else {
            drop()
            return false
        }
        entry.isSuspect = false
        revalidation.counts.rechecked += 1
        return true
    }
}
