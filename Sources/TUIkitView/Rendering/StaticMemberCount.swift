//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StaticMemberCount.swift
//
//  How many children a view hands its container, known from its type alone —
//  what lets a `ForEach` whose rows are several views each map a child's
//  ordinal to its element by arithmetic, so a lazy stack over a million such
//  rows still builds only the rows it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A provider that knows from its TYPE how many children it hands the
/// container resolving it — `nil` when that depends on the instance (an `if`
/// whose arms differ, an `if` without `else`, a loop, a section).
///
/// Asked through ``staticMemberCount(_:)``, which answers for the types that
/// do not conform: one for any view that is no provider, none for `EmptyView`
/// (under any wrappers that draw nothing of their own), the content's count
/// for a provider that wraps one view (``ContentRewrapping``), and `nil` —
/// "build the row and count" — for any other provider. So a provider added
/// later is counted correctly by default, only more slowly.
///
/// A count is a promise every walk relies on: a loop whose rows count `k`
/// each is `k` children per element to a lazy stack, a list and the subview
/// APIs, which never build a row to check. So `nil` is the answer whenever an
/// instance can make any other number — an `if` without `else` makes none
/// while its condition is false.
@MainActor
package protocol StaticMemberCounting {
    /// How many children an instance of this type contributes, or `nil` when
    /// that depends on the instance.
    static var staticMemberCount: Int? { get }

    /// How many children an instance contributes when it is a `ForEach`'s
    /// whole row, or `nil` — ``staticMemberCount`` for every type but an `if`
    /// without `else` around one view (see ``staticRowMemberCount(_:)``).
    static var staticRowMemberCount: Int? { get }
}

extension StaticMemberCounting {
    package static var staticRowMemberCount: Int? { staticMemberCount }
}

/// How many children a view of type `type` contributes to the container
/// resolving it — see ``StaticMemberCounting``.
///
/// An `EmptyView` contributes none, as SwiftUI counts it, and so does one
/// under wrappers that draw nothing of their own (`EmptyView().padding()`),
/// which the walks drop the same way (`isEmptyMember`). A view that is no
/// ``ChildViewProvider`` — almost every view — is one child.
@MainActor
package func staticMemberCount<V: View>(_ type: V.Type) -> Int? {
    if let counting = type as? any StaticMemberCounting.Type { return counting.staticMemberCount }
    if type == EmptyView.self { return 0 }
    guard type is any ChildViewProvider.Type else { return wrapsOnlyEmptyView(type) ? 0 : 1 }
    // A wrapper that is a provider because its content is hands over its
    // content's children, one for one.
    if let wrapper = type as? any ContentRewrapping.Type { return wrappedMemberCount(wrapper) }
    return nil
}

/// How many children a view of type `type` contributes as a `ForEach`'s whole
/// row: ``staticMemberCount(_:)``, except that an `if` without `else` around
/// ONE view is one, and so is an `AnyView` — through the wrappers that hand
/// over their content's children, too. A loop places such a row whole — one
/// child, drawing nothing while an `if`'s condition is false — as it always
/// has here, where SwiftUI counts none for the `if` and what it erases for the
/// `AnyView` (decisions D1S, B-D1S-3, B-D1S-5): counting it as it is spliced
/// would build every row of a loop that filters its elements with an `if`, or
/// erases its rows, to learn how many views each is.
@MainActor
package func staticRowMemberCount<V: View>(_ type: V.Type) -> Int? {
    if let counting = type as? any StaticMemberCounting.Type { return counting.staticRowMemberCount }
    if type is any ChildViewProvider.Type, let wrapper = type as? any ContentRewrapping.Type {
        return wrappedRowMemberCount(wrapper)
    }
    return staticMemberCount(type)
}

/// ``staticRowMemberCount(_:)`` of a wrapper's content, the existential opened.
@MainActor
private func wrappedRowMemberCount<W: ContentRewrapping>(_: W.Type) -> Int? {
    staticRowMemberCount(W.WrappedContent.self)
}

/// ``staticMemberCount(_:)`` of a wrapper's content, the existential opened.
@MainActor
private func wrappedMemberCount<W: ContentRewrapping>(_: W.Type) -> Int? {
    staticMemberCount(W.WrappedContent.self)
}

/// Whether `type` is an `EmptyView` under nothing but single-content
/// wrappers — what `isEmptyMember` finds at run time, `throughWrappers`
/// answered from the type.
@MainActor
private func wrapsOnlyEmptyView<V: View>(_ type: V.Type) -> Bool {
    if type == EmptyView.self { return true }
    guard let wrapper = type as? any SingleContentWrapper.Type else { return false }
    return wrappedIsOnlyEmptyView(wrapper)
}

/// ``wrapsOnlyEmptyView(_:)`` of a wrapper's content, the existential opened.
@MainActor
private func wrappedIsOnlyEmptyView<W: SingleContentWrapper>(_: W.Type) -> Bool {
    wrapsOnlyEmptyView(W.WrappedContent.self)
}

// MARK: - The Framework's Own Providers

extension TupleView: StaticMemberCounting {
    /// The sum of the elements' counts, if each has one.
    package static var staticMemberCount: Int? {
        var total: Int? = 0
        func add<T: View>(_: T.Type) {
            guard let sum = total, let count = TUIkitView.staticMemberCount(T.self) else {
                total = nil
                return
            }
            total = sum + count
        }
        repeat add((each V).self)
        return total
    }
}

extension ConditionalView: StaticMemberCounting {
    /// The arms' count when they agree; otherwise it depends on which is live.
    package static var staticMemberCount: Int? {
        let whenTrue = TUIkitView.staticMemberCount(TrueContent.self)
        return whenTrue == TUIkitView.staticMemberCount(FalseContent.self) ? whenTrue : nil
    }
}

extension Optional: StaticMemberCounting where Wrapped: View {
    /// Never known: spliced into its container, an `if` without `else` hands
    /// over its content's children while its condition holds and none while
    /// it does not — or, while what it held is still leaving, the one slot
    /// that plays the removal (`Optional.childViews`). So a row of several
    /// views with one among them — `Text(name); if flagged { Text("!") }` —
    /// is built and counted, never taken for a fixed number.
    package static var staticMemberCount: Int? { nil }

    /// One for an `if` around one view that is a loop's whole row: the loop
    /// places it whole, as it always has (``staticRowMemberCount(_:)``).
    package static var staticRowMemberCount: Int? {
        TUIkitView.staticMemberCount(Wrapped.self) == 1 ? 1 : nil
    }
}

extension ModifiedView: StaticMemberCounting where Content: ChildViewProvider {
    /// The content's: a modifier on several views reaches each of them.
    package static var staticMemberCount: Int? { TUIkitView.staticMemberCount(Content.self) }

    /// The content's, as a loop's whole row.
    package static var staticRowMemberCount: Int? { TUIkitView.staticRowMemberCount(Content.self) }
}
