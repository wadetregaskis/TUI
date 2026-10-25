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

    /// What ``eligibility(ofRowsOf:)`` has answered, by type.
    private var eligibilities: [ObjectIdentifier: RowEligibility] = [:]

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
