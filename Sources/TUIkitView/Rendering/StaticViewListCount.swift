//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StaticViewListCount.swift
//
//  How many views a type puts where it is written, counted as SwiftUI counts
//  them from the type alone — what decides whether a stack reports an edge
//  or centre guide out of itself.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A type that says how many views it puts where it is written, counted from
/// the type alone as SwiftUI counts them, or `nil` when the count depends on
/// the instance — see ``staticViewListCount(_:)``.
@MainActor
package protocol StaticViewListCounting {
    /// How many views a value of this type puts where it is written, or `nil`
    /// when that depends on the value.
    static var staticViewListCount: Int? { get }
}

/// How many views a value of `type` puts where it is written, counted from the
/// type alone as SwiftUI counts them, or `nil` when that depends on the value.
///
/// SwiftUI's stacks report an edge or centre guide (`.leading`, `.top`, …)
/// out of themselves only when their content is statically one view, and this
/// is that count (measured, decisions A-GUIDE-2,
/// `Tools/SwiftUIProbes/Alignment guides/layout1.out`): `VStack { G }`,
/// `VStack { G; EmptyView() }`, `VStack { Group { G } }`, `VStack { G.padding(0)
/// }` and a view of the app's own whose body is `G` count one; a `ForEach`
/// of one row, an `if`, an `if`/`else` — even one whose arms are each one view
/// — and a view of the app's own whose body is one of those count none known.
///
/// Not ``staticMemberCount(_:)``, which answers how many children TUIkit's
/// containers resolve and counts an `if`/`else` whose arms agree, so a loop of
/// such rows stays lazy. The rules here are SwiftUI's: `EmptyView` is none, a
/// tuple the sum of its elements, a `Group` its content, a single-content
/// wrapper — a modifier — its content, any other provider unknown, a view of
/// the app's own its body (unknown where its body holds its own type), and
/// any other view one.
@MainActor
package func staticViewListCount<V: View>(_ type: V.Type) -> Int? {
    if let counting = type as? any StaticViewListCounting.Type { return counting.staticViewListCount }
    if type == EmptyView.self { return 0 }
    if let wrapper = type as? any SingleContentWrapper.Type { return wrappedViewListCount(wrapper) }
    if type is any ChildViewProvider.Type { return nil }
    guard V.Body.self != Never.self, !(type is any Renderable.Type) else { return 1 }
    return CompositeBodyDescent.counting(type) { staticViewListCount(V.Body.self) }
}

/// Whether a value of `type` is statically one view (``staticViewListCount(_:)``
/// is one), kept per type (``BodyWitnessMemo``): for a container that asks it
/// of its content on every walk — a stack of one view passes an unspecified
/// width on to it, as SwiftUI's does.
@MainActor
package func isStaticallyOneView<V: View>(_ type: V.Type) -> Bool {
    BodyWitnessMemo.answer(in: BodyWitnessMemo.staticallyOneView, for: type) { staticViewListCount(type) == 1 }
}

/// ``staticViewListCount(_:)`` of a wrapper's content, the existential opened.
@MainActor
private func wrappedViewListCount<W: SingleContentWrapper>(_: W.Type) -> Int? {
    staticViewListCount(W.WrappedContent.self)
}

extension TupleView: StaticViewListCounting {
    /// The sum of the elements' counts, if each has one.
    package static var staticViewListCount: Int? {
        var total: Int? = 0
        func add<T: View>(_: T.Type) {
            guard let sum = total, let count = TUIkitView.staticViewListCount(T.self) else {
                total = nil
                return
            }
            total = sum + count
        }
        repeat add((each V).self)
        return total
    }
}
