//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ForEachSubviewCollection.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - A Collection Resolved by Context

/// A collection a `ForEach` can only iterate once a context has resolved it —
/// the members of a view, whose identities exist only under the scope they
/// resolve in.
///
/// `ForEach` stores its data from `init`, which has no context. A collection
/// conforming to this is stored unresolved, and empty; ``ForEach/data(in:)``
/// resolves it on every walk that has a context. A walk without one sees it
/// empty, so it draws nothing rather than rows it cannot account for.
@MainActor
package protocol ContextResolvedCollection {
    /// This collection with its elements resolved in `context`.
    func resolved(in context: RenderContext) -> Self
}

extension ForEach where Content: View {
    /// ``data`` resolved in `context`, for a collection that needs one —
    /// see ``ContextResolvedCollection``.
    ///
    /// The metatype test is the whole cost for every other loop: one per walk
    /// of a `ForEach`, never one per row.
    func contextResolvedData(in context: RenderContext) -> Data? {
        guard Data.self is any ContextResolvedCollection.Type,
            let resolvable = data as? any ContextResolvedCollection
        else { return nil }
        return resolvable.resolved(in: context) as? Data
    }
}

// MARK: - ForEach(subviews:content:)

extension ForEach where Content: View {
    /// Creates an instance that uniquely identifies and creates views across
    /// updates based on the subviews of a given view.
    ///
    /// One row per member of `view` — the members ``Group/init(subviews:transform:)``
    /// hands its transform — each identified by its ``Subview/id``, so a row's
    /// `@State` follows its member across updates and reordering.
    ///
    /// ```swift
    /// VStack {
    ///     ForEach(subviews: content) { subview in
    ///         subview
    ///             .padding()
    ///             .border()
    ///     }
    /// }
    /// ```
    ///
    /// Subviews are proxies to the resolved views they represent: modifiers on
    /// the original view apply before modifiers applied to the subview.
    ///
    /// The members are resolved where the loop is drawn, so this works wherever
    /// a `ForEach` is laid out as views — a stack, a `Layout`, a `Group`, on its
    /// own. `List`, `Picker`, `TabView`, `Form` and text-input suggestions read
    /// their rows without drawing them, and see this loop as empty.
    ///
    /// - Parameters:
    ///   - view: The view to extract the subviews of.
    ///   - content: The view builder that creates views from subviews.
    public init<V: View>(
        subviews view: V, @ViewBuilder content: @escaping (Subview) -> Content
    ) where Data == ForEachSubviewCollection<Content>, ID == Subview.ID {
        self.init(ForEachSubviewCollection(source: view), id: \.id, content: content)
    }
}

/// A collection which allows a view to be treated as a collection of its
/// subviews in a for each loop.
///
/// You don't use this type directly: ``ForEach/init(subviews:content:)``
/// creates it.
@MainActor
public struct ForEachSubviewCollection<Content: View> {
    /// The view whose members this iterates.
    let source: any View

    /// The members, once resolved; empty until then.
    let members: SubviewMembers

    init(source: some View) {
        self.source = source
        self.members = .empty
    }

    private init(source: any View, members: SubviewMembers) {
        self.source = source
        self.members = members
    }
}

extension ForEachSubviewCollection: @MainActor RandomAccessCollection {
    public typealias Element = Subview
    public typealias Index = Int
    public typealias Indices = Range<Int>

    public var startIndex: Int { 0 }

    public var endIndex: Int { members.count }

    public subscript(position: Int) -> Subview {
        Subview(members: members, index: position)
    }
}

extension ForEachSubviewCollection: ContextResolvedCollection {
    /// The source's members, resolved under a step of their own below the
    /// loop, so they cannot share an identity with the rows the loop builds
    /// from them — the namespace ``Group/init(subviews:transform:)`` keeps
    /// between its members and its result.
    package func resolved(in context: RenderContext) -> Self {
        func resolve<V: View>(_ source: V) -> SubviewMembers {
            SubviewMembers(resolving: source, in: context.withChildIdentity(type: V.self, index: 0))
        }
        return Self(source: source, members: resolve(source))
    }
}
