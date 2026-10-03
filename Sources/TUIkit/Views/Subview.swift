//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Subview.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Subview

/// An opaque value representing a subview of another view.
///
/// You get one from ``Group/init(subviews:transform:)`` or
/// ``ForEach/init(subviews:content:)``. A subview is a proxy for the resolved
/// view it stands for, and draws that view where you place it:
///
/// - Modifiers written on the original view apply before modifiers applied to
///   the proxy — `.foregroundStyle` on the proxy reaches the view, and the
///   view's own `.foregroundStyle` wins over it.
/// - Its ``id`` is the identity the view resolved to, so it is the same across
///   updates and across reordering, and the view's `@State` and focus follow it.
/// - Placed twice, it draws twice — one view, with one `@State`, in two
///   places, as in SwiftUI.
///
/// A proxy reports its view's size but not that the view is a `Spacer`, nor
/// any `.alignmentGuide` on it: a container that should see those reads the
/// collection itself (`HStack { subviews }`), which hands it the members as
/// its own children.
public struct Subview: View, @MainActor Identifiable {
    /// The member, its identity pinned where it was resolved.
    let child: ChildView

    /// The members this one was taken from, and its index among them — where
    /// the element id a `ForEach` row is tagged with is asked, lazily.
    private let members: SubviewMembers
    private let index: Int

    init(members: SubviewMembers, index: Int) {
        self.child = members.child(at: index)
        self.members = members
        self.index = index
    }

    /// A unique identifier for a subview.
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        /// The identity the subview's view resolved to.
        let identity: ViewIdentity

        public var description: String { identity.description }
    }

    /// The unique identifier of the view.
    ///
    /// The identity the view resolved to: it persists across updates and
    /// changes to the order of subviews, so it can track a subview's lifetime.
    public var id: ID {
        guard let identity = child.pinnedIdentity else {
            preconditionFailure("a subview's member is pinned by the walk that resolved it")
        }
        return ID(identity: identity)
    }

    /// The container values associated with the given subview — what
    /// ``View/containerValue(_:_:)`` and ``View/tag(_:includeOptional:)`` set on
    /// it, and the element id a `ForEach` row is tagged with.
    public var containerValues: ContainerValues {
        ContainerValues(of: child, implicitTag: members.implicitTag(at: index))
    }

    public var body: some View {
        _SubviewCore(child: child)
    }
}

extension Subview {
    /// Options on how all subviews should be sized when in a container.
    ///
    /// Not about how one view measures alone: it describes the sizing of a
    /// group of subviews together, and only a container acts on it. Nothing in
    /// SwiftUI's own API takes one yet, and nothing here does either.
    public enum ContainerSizingOptions: Hashable, Sendable {
        /// Subviews will share the same size.
        case uniform(axis: Axis.Set)

        /// Subviews will be sized individually.
        case variable
    }
}

/// Draws a subview's member: measured and rendered with the context of the
/// place the proxy is put, at the identity the member was pinned to.
private struct _SubviewCore: View, Renderable, Layoutable {
    let child: ChildView

    var body: Never {
        fatalError("_SubviewCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        child.measure(proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        child.render(
            width: max(0, context.availableWidth), height: max(0, context.availableHeight),
            context: context)
    }
}

// MARK: - Subviews Collection

/// An opaque collection representing the subviews of a view.
///
/// The collection builds subviews on demand, so access only the part you need.
/// Its elements are the pieces that make up the view; the collection as a whole
/// is also a view, and a proxy for the original: placed in a container, it
/// contributes each member as a separate child, so `HStack { subviews }` lays
/// them out side by side and `subviews[1...]` contributes all but the first.
/// Placed where nothing lays its members out, it stacks them vertically, as a
/// `ForEach` does.
public struct SubviewsCollection: View {
    let members: SubviewMembers

    public var body: some View {
        _SubviewMembersCore(members: members, range: 0..<members.count)
    }
}

extension SubviewsCollection: @MainActor RandomAccessCollection {
    public typealias Element = Subview
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias SubSequence = SubviewsCollectionSlice

    public var startIndex: Int { 0 }

    public var endIndex: Int { members.count }

    public func index(after i: Int) -> Int { i + 1 }

    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position: Int) -> Subview {
        Subview(members: members, index: position)
    }

    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice {
        SubviewsCollectionSlice(members: members, bounds: bounds)
    }
}

extension SubviewsCollection: ChildViewProvider, LazyChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        members.children(0..<members.count)
    }

    public func childViewCollection(context: RenderContext) -> ChildViewCollection {
        members.childViewCollection(0..<members.count)
    }
}

// MARK: - Subviews Collection Slice

/// A slice of a ``SubviewsCollection``.
///
/// Keeps its parent's indices, as every `Collection` slice does: in
/// `subviews[1...]` the first member is at index 1.
public struct SubviewsCollectionSlice: View {
    let members: SubviewMembers
    let bounds: Range<Int>

    public var body: some View {
        _SubviewMembersCore(members: members, range: bounds)
    }
}

extension SubviewsCollectionSlice: @MainActor RandomAccessCollection {
    public typealias Element = Subview
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias SubSequence = SubviewsCollectionSlice

    public var startIndex: Int { bounds.lowerBound }

    public var endIndex: Int { bounds.upperBound }

    public subscript(position: Int) -> Subview {
        Subview(members: members, index: position)
    }

    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice {
        SubviewsCollectionSlice(members: members, bounds: bounds)
    }
}

extension SubviewsCollectionSlice: ChildViewProvider, LazyChildViewProvider {
    public func childViews(context: RenderContext) -> [ChildView] {
        members.children(bounds)
    }

    public func childViewCollection(context: RenderContext) -> ChildViewCollection {
        members.childViewCollection(bounds)
    }
}

// MARK: - Drawn Alone

/// A run of members nothing above laid out: stacked vertically, as a
/// `ForEach` that is a view's whole body is.
private struct _SubviewMembersCore: View, Renderable, Layoutable {
    let members: SubviewMembers
    let range: Range<Int>

    var body: Never {
        fatalError("_SubviewMembersCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureStackedVertically(members.children(range), proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        renderStackedVertically(members.children(range), context: context)
    }
}
