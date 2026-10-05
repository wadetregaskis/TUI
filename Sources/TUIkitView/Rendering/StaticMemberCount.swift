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
/// whose arms differ, a loop, a section).
///
/// Asked through ``staticMemberCount(_:)``, which answers for the types that
/// do not conform: one for any view that is no provider, none for `EmptyView`,
/// the content's count for a provider that wraps one view
/// (``ContentRewrapping``), and `nil` — "build the row and count" — for any
/// other provider. So a provider added later is counted correctly by default,
/// only more slowly.
@MainActor
package protocol StaticMemberCounting {
    /// How many children an instance of this type contributes, or `nil` when
    /// that depends on the instance.
    static var staticMemberCount: Int? { get }
}

/// How many children a view of type `type` contributes to the container
/// resolving it — see ``StaticMemberCounting``.
///
/// An `EmptyView` contributes none, as SwiftUI counts it. A view that is no
/// ``ChildViewProvider`` — almost every view — is one child.
@MainActor
package func staticMemberCount<V: View>(_ type: V.Type) -> Int? {
    if let counting = type as? any StaticMemberCounting.Type { return counting.staticMemberCount }
    if type == EmptyView.self { return 0 }
    guard type is any ChildViewProvider.Type else { return 1 }
    // A wrapper that is a provider because its content is hands over its
    // content's children, one for one.
    if let wrapper = type as? any ContentRewrapping.Type { return wrappedMemberCount(wrapper) }
    return nil
}

/// ``staticMemberCount(_:)`` of a wrapper's content, the existential opened.
@MainActor
private func wrappedMemberCount<W: ContentRewrapping>(_: W.Type) -> Int? {
    staticMemberCount(W.WrappedContent.self)
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
    /// One for an optional view of one: a `nil` is an empty member of its
    /// container, as an `if` around one view always was here. Around several,
    /// it depends on whether there is any.
    package static var staticMemberCount: Int? {
        switch TUIkitView.staticMemberCount(Wrapped.self) {
        case 0: 0
        case 1: 1
        default: nil
        }
    }
}

extension ModifiedView: StaticMemberCounting where Content: ChildViewProvider {
    /// The content's: a modifier on several views reaches each of them.
    package static var staticMemberCount: Int? { TUIkitView.staticMemberCount(Content.self) }
}
