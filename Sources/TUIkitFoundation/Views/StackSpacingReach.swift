//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StackSpacingReach.swift
//
//  Which edges a view's spacing preference can reach, asked of its type: what
//  lets a row skip a child whose preference can only be on edges the row
//  never reads.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// Whether a view of `type` may state a spacing preference on its edges along
/// `axis` — its leading and trailing edges for `.horizontal`, its top and
/// bottom ones for `.vertical` — from its type alone.
///
/// ``View/_statesSpacingPreference`` says whether a view may state one on any
/// edge, and a row reads only its children's leading and trailing ones. A
/// column's leading and trailing edges are every one of its views' but a
/// spacer's, whose "none" is about the column's own axis
/// (`edgesFormed(by:along:context:)`), so a column whose only views that state
/// one are spacers states nothing a row can read. Asked through the witness
/// alone, a row beside `struct SideBar: View { var body: some View { VStack {
/// Text("side"); Spacer() } } }` evaluated `SideBar`'s body again and
/// resolved its column on every walk, to find nothing (found in review of
/// decisions B-BITEMS1-3).
///
/// `true` wherever the type does not say otherwise — `false` skips a walk
/// that would have found nothing, so a `true` too many costs only that walk.
/// Kept per type and axis (``BodyWitnessMemo``), as the witness is: a row asks
/// it of every child whose witness says "may".
@MainActor
func mayStateSpacing<V: View>(_ type: V.Type, along axis: Axis) -> Bool {
    guard V._statesSpacingPreference else { return false }
    let memo = axis == .horizontal ? BodyWitnessMemo.spacingAlongHorizontal : BodyWitnessMemo.spacingAlongVertical
    return BodyWitnessMemo.answer(in: memo, for: type) { spacingReach(of: type, along: axis) }
}

/// ``mayStateSpacing(_:along:)`` of a child, its view opened.
@MainActor
func mayStateSpacing(_ child: ChildView, along axis: Axis) -> Bool {
    func reach<V: View>(_: V) -> Bool { mayStateSpacing(V.self, along: axis) }
    return reach(child.wrappedView)
}

/// ``mayStateSpacing(_:along:)`` worked out, past the witness — in the order
/// `statedSpacing(ofView:context:)` asks: a type that says itself (a stack by
/// the edges its views form), a view that is several by any of them, any
/// other view that states one itself as "may", a wrapper by its content, a
/// view of the app's own by its body.
@MainActor
private func spacingReach<V: View>(of type: V.Type, along axis: Axis) -> Bool {
    if let reaching = type as? any SpacingReaching.Type { return reaching.mayStateSpacing(along: axis) }
    if let several = type as? any SpacingMembers.Type {
        return several.anyMemberMayStateSpacing(along: axis, countingSpacers: true)
    }
    if type is any SpacingPreferenceProviding.Type { return true }
    if let wrapper = type as? any SingleContentWrapper.Type { return wrappedMayStateSpacing(wrapper, along: axis) }
    guard V.Body.self != Never.self, !(type is any Renderable.Type) else { return true }
    return mayStateSpacing(V.Body.self, along: axis)
}

/// ``mayStateSpacing(_:along:)`` of a wrapper's content, the existential
/// opened.
@MainActor
private func wrappedMayStateSpacing<W: SingleContentWrapper>(_: W.Type, along axis: Axis) -> Bool {
    mayStateSpacing(W.WrappedContent.self, along: axis)
}

/// Whether a view of `type`, as a member of a stack, may state a spacing
/// preference on the stack's edges along `axis`: a spacer only where
/// `countingSpacers` — along the stack's own axis, not across it — and a view
/// that is several by any of its members.
@MainActor
private func memberMayStateSpacing<V: View>(_ type: V.Type, along axis: Axis, countingSpacers: Bool) -> Bool {
    guard V._statesSpacingPreference else { return false }
    if type == Spacer.self { return countingSpacers }
    if let several = type as? any SpacingMembers.Type {
        return several.anyMemberMayStateSpacing(along: axis, countingSpacers: countingSpacers)
    }
    return mayStateSpacing(type, along: axis)
}

// MARK: - The types that say

/// A view type that answers ``mayStateSpacing(_:along:)`` itself, where the
/// generic reading — "may" for any view that states a preference itself —
/// says more than it can.
@MainActor
protocol SpacingReaching {
    /// Whether a view of this type may state a preference on its edges along
    /// `axis`.
    static func mayStateSpacing(along axis: Axis) -> Bool
}

// MARK: - The stacks

// An eager stack states the edges its views form
// (`edgesFormed(by:along:context:)`): along its own axis its first view's and
// its last one's, a spacer's among them; across, every view's but a spacer's.

extension _VStackCore: SpacingReaching {
    static func mayStateSpacing(along axis: Axis) -> Bool {
        memberMayStateSpacing(Content.self, along: axis, countingSpacers: axis == .vertical)
    }
}

extension _HStackCore: SpacingReaching {
    static func mayStateSpacing(along axis: Axis) -> Bool {
        memberMayStateSpacing(Content.self, along: axis, countingSpacers: axis == .horizontal)
    }
}

// MARK: - The views that are several

/// A view that is several to the stack laying it out — a tuple, an `if`, a
/// group, a loop — whose members state their own preferences.
@MainActor
protocol SpacingMembers {
    /// Whether any member may state a preference on the stack's edges along
    /// `axis` (``memberMayStateSpacing(_:along:countingSpacers:)``).
    static func anyMemberMayStateSpacing(along axis: Axis, countingSpacers: Bool) -> Bool
}

extension TupleView: SpacingMembers {
    static func anyMemberMayStateSpacing(along axis: Axis, countingSpacers: Bool) -> Bool {
        var found = false
        func ask<T: View>(_: T.Type) {
            if !found, memberMayStateSpacing(T.self, along: axis, countingSpacers: countingSpacers) { found = true }
        }
        repeat ask((each V).self)
        return found
    }
}

extension ConditionalView: SpacingMembers {
    static func anyMemberMayStateSpacing(along axis: Axis, countingSpacers: Bool) -> Bool {
        memberMayStateSpacing(TrueContent.self, along: axis, countingSpacers: countingSpacers)
            || memberMayStateSpacing(FalseContent.self, along: axis, countingSpacers: countingSpacers)
    }
}

extension Optional: SpacingMembers where Wrapped: View {
    static func anyMemberMayStateSpacing(along axis: Axis, countingSpacers: Bool) -> Bool {
        memberMayStateSpacing(Wrapped.self, along: axis, countingSpacers: countingSpacers)
    }
}

extension Group: SpacingMembers where Content: View {
    static func anyMemberMayStateSpacing(along axis: Axis, countingSpacers: Bool) -> Bool {
        memberMayStateSpacing(Content.self, along: axis, countingSpacers: countingSpacers)
    }
}

extension ForEach: SpacingMembers where Content: View {
    static func anyMemberMayStateSpacing(along axis: Axis, countingSpacers: Bool) -> Bool {
        memberMayStateSpacing(Content.self, along: axis, countingSpacers: countingSpacers)
    }
}
