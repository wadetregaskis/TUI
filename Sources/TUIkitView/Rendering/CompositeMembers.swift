//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeMembers.swift
//
//  A view of the app's own whose `body` is several views is, to the container
//  resolving it, those views — as SwiftUI's is.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - The Bodies That Are Taken Apart

extension TupleView {
    /// A tuple of views is several (``View/_handsOverChildren``).
    public static var _handsOverChildren: Bool { true }
}

extension Optional where Wrapped: View {
    /// An `if` without `else` is none of its view while its condition is false
    /// (``View/_handsOverChildren``).
    public static var _handsOverChildren: Bool { true }
}

// An `if`/`else` (`ConditionalView`), an `AnyView` and a modifier answer the
// default — their `body` is `Never` — so a view whose body is one of them is
// the one child it was: an `if`/`else` of one view each, the body of most of
// the framework's own controls (`TextField`'s is), hands over one view either
// way, and taking it apart would evaluate the body on every walk for nothing.

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
/// Gated by ``View/_handsOverChildren`` — a few witness calls down the chain
/// of `body` types — so a view whose body is a stack, a `Text`, or anything
/// else that is one view is never evaluated here.
///
/// A view nested in itself through such bodies is taken apart at every level
/// at once, each level a descent of this walk, so the walk stops where the
/// stack runs short (`StackGuard.hasHeadroomUncounted()`): the view is then
/// the one child it was, drawn whole, and its own descent truncates under the
/// render's guard, which counts.
@MainActor
package func compositeMembers<V: View>(of view: V, context: RenderContext) -> [ChildView]? {
    guard V._handsOverChildren, V.Body.self != Never.self, context.stateStorage != nil,
        !(V.self is any ChildViewProvider.Type), !(V.self is any Renderable.Type),
        StackGuard.hasHeadroomUncounted()
    else { return nil }
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
