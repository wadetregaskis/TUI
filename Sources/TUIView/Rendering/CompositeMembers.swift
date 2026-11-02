//  🖥️ TUI — A Terminal UI framework for Swift
//  CompositeMembers.swift
//
//  A view of the app's own whose `body` is several views is, to the container
//  resolving it, those views — as SwiftUI's is.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - The Bodies That Are Taken Apart

@MainActor extension TupleView {
    /// A tuple of views is several (``View/_handsOverChildren``).
    public static var _handsOverChildren: Bool { true }
}

extension Optional where Wrapped: View {
    /// An `if` without `else` is none of its view while its condition is false
    /// (``View/_handsOverChildren``).
    public static var _handsOverChildren: Bool { true }
}

@MainActor extension ConditionalView {
    /// An `if`/`else` hands over what its live arm hands over, so it may hand
    /// over several when either arm may (``View/_handsOverChildren``) — and a
    /// view whose body is one is taken apart, as SwiftUI's is (measured,
    /// `Tools/SwiftUIProbes/Sections and subview counting/composite-bodies.out`:
    /// `if flag { a; b } else { c }` as a body lays `a` and `b` along an
    /// `HStack`). An `if`/`else` of one view each — the body of many of the
    /// framework's own controls (`TextField`'s is) — answers `false`, and is
    /// never evaluated to find out. One of one view and an `EmptyView` answers
    /// `true`, as an `if` does: it is one view or none, and a loop still
    /// places it whole (``staticRowMemberCount(_:)``).
    public static var _handsOverChildren: Bool {
        TrueContent._handsOverChildren || FalseContent._handsOverChildren
    }
}

@MainActor extension ModifiedView {
    /// A modifier on views that hand over several hands over each of them,
    /// modified (`ModifiedView`'s ``ChildViewProvider`` conformance) — so a
    /// view whose body is `Group { a; b }.padding()` is `a` and `b`, each
    /// padded, as SwiftUI's is (``View/_handsOverChildren``).
    public static var _handsOverChildren: Bool { Content._handsOverChildren }
}

extension View where Self: ContentRewrapping {
    /// A wrapper that hands its content's members on, each inside a copy of
    /// itself, hands over what its content does (``View/_handsOverChildren``):
    /// `Group { a; b }.frame(width: 3)` as a body is `a` and `b`, each framed.
    /// The effect wrappers (`.onAppear`, `.task`, …) are not
    /// ``ContentRewrapping``, and answer `false`: SwiftUI fires such an effect
    /// on several views once, so a view whose body is one stays one child.
    public static var _handsOverChildren: Bool { WrappedContent._handsOverChildren }
}

// An `AnyView` answers `false` — what it erases is not in its type — so a view
// whose body is one is the one child it was.

/// The children a view of the app's own hands the container resolving it,
/// when its `body` is a provider of children, or `nil` for any other view —
/// which is the one child it always was.
///
/// Measured on macOS 15.8
/// (`Tools/SwiftUIProbes/Sections and subview counting/composite.swift`): `struct Rows: View { var
/// body: some View { a; b } }` beside a view is three subviews of a `Layout`,
/// an `HStack` lays all three along its row, a `VStack` spaces each, a `ZStack`
/// overlaps them, `Group(subviews:)` counts two, a `List` draws three rows; so
/// is one inside another, a body that is a loop (each row), and one that is an
/// `if` (none while false). Here such a view was one child everywhere, its body
/// stacked in a column (decisions D1S, B-D1S-6).
///
/// `context` is the view's own — the identity it would draw at as one child.
/// Its body is evaluated as a render evaluates it (`evaluateCompositeBody`:
/// `@State` bound at that identity, `@Environment` resolved, observed) and
/// resolved one identity step in, where the render walk puts a body, each
/// child pinned there: so the view keeps its `@State`, and every view of its
/// body the identity, the `@State` and the render-cache entries it had when
/// the view was drawn whole.
///
/// Gated by ``View/_handsOverChildren`` — its type's kept answer, worked out
/// once down the chain of `body` types — so a view whose body is a stack, a
/// `Text`, or anything else that is one view is never evaluated here.
///
/// A view nested in itself through such bodies is taken apart at every level
/// at once, each level a descent of this walk, so the walk stops where the
/// stack runs short (`StackGuard.hasHeadroomUncounted()`): the view is then
/// the one child it was, drawn whole, and its own descent truncates under the
/// render's guard, which counts.
@MainActor
package func compositeMembers<V: View>(of view: V, context: RenderContext) -> [ChildView]? {
    guard V._handsOverChildren, V.Body.self != Never.self, context.stateStorage != nil,
        !(V.self is any ChildViewProvider.Type), !(V.self is any Renderable.Type)
    else { return nil }
    guard StackGuard.hasHeadroomUncounted() else {
        StackGuard.noteReadThroughStop()
        return nil
    }
    // What the body's walk hands the `@Environment`s in a class property the
    // view holds, as other than the object's primary holder, is put back only
    // after the content of the composite around the container, not after
    // these members: the container draws them among its other children
    // (decisions-DYNVFIX B-DYNVFIX-3, "Left").
    let body = evaluateCompositeBody(of: view, context: context)
    let bodyContext = context.withChildIdentity(type: V.Body.self)
    return resolveChildViews(from: body, context: bodyContext).map {
        $0.pinningIdentity(to: bodyContext.identity)
    }
}
