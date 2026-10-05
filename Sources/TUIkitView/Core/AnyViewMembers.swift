//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnyViewMembers.swift
//
//  An `AnyView` around several views hands its container each of them, as
//  SwiftUI's does: type erasure hides the type, not the structure.
//
//  Created by Wade Tregaskis
//  License: MIT

/// An `AnyView` is, to the container resolving it, what it erases: one child
/// when that is one view, as it always was, and each of its views when it is
/// several — measured on macOS 15.8 (`D1S/probe/b15`): `AnyView(Group { a; b })`
/// is two subviews of a `Layout`, an `HStack` lays the two along its row, and
/// the Wave 5 probe counted the same. Until then an `AnyView` was one child
/// everywhere, so the same `HStack` stacked the pair in a column (decisions
/// D1S, B-D1S-3).
///
/// Whole (``staysWhole(in:)``) unless what it erases is a provider of children
/// taken apart there, so an `AnyView` around one view is the child it always
/// was, at the identity it always had: every walk that expands a provider asks
/// first. Taken apart, its views resolve as its content's would, under the
/// step the walk gives the `AnyView` — the erased type's own steps below that
/// keep two erased contents of different types apart, as the erasure's type
/// note does for content drawn whole (`AnyView.contentContext(noting:)`).
///
/// As a `ForEach`'s row an `AnyView` stays one child (``StaticMemberCounting``):
/// its type cannot say how many views it holds, and building every row to
/// count them would cost a loop of erased rows its row memo and a lazy stack
/// its window.
extension AnyView: ChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        // Whole, for a caller that asks a provider for its children without
        // asking first whether it stays whole.
        guard let provider = erasedView as? ChildViewProvider, !provider.staysWhole(in: context) else {
            return [ChildView(self)]
        }
        return erasedMembers(of: erasedView, as: provider, context: context)
    }

    public func staysWhole(in context: RenderContext) -> Bool {
        guard let provider = erasedView as? ChildViewProvider else { return true }
        return provider.staysWhole(in: context)
    }
}

/// The children of `view`, which `provider` is — the existential opened.
@MainActor
private func erasedMembers<V: View>(of view: V, as provider: ChildViewProvider, context: RenderContext)
    -> [ChildView]
{
    resolveChildViews(from: view, as: provider, context: context)
}

extension AnyView: StaticMemberCounting {
    /// Never known: what is erased may be several views.
    package static var staticMemberCount: Int? { nil }

    /// One, as a `ForEach`'s whole row: the loop places such a row whole, as
    /// it always has (see the conformance to ``ChildViewProvider``).
    package static var staticRowMemberCount: Int? { 1 }
}
