//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Group.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Group

/// A view that collects multiple views into a single unit, without imposing
/// any layout of its own.
///
/// `Group` is transparent: it renders its children exactly as if they had
/// been written in its place. Use it to apply a modifier to several views at
/// once, to return more than one view from a branch, or to exceed the
/// ten-view limit of a single `@ViewBuilder` block.
///
/// ```swift
/// VStack {
///     Group {
///         Text("First")
///         Text("Second")
///     }
///     .foregroundStyle(.palette.accent)
///
///     Text("Third")
/// }
/// ```
///
/// `Group` is not only a view: as in SwiftUI it also groups table columns and
/// table rows, and it is a view exactly when what it groups is one.
public struct Group<Content> {
    /// The grouped content.
    package let content: Content

    /// Stores `content`, already built. Declared, and `fileprivate`, so that
    /// no memberwise `init(content:)` exists for a trailing closure to bind
    /// to: with `Content` unconstrained, `Group { … }` would otherwise match it
    /// with the closure itself as the content.
    fileprivate init(grouping content: Content) {
        self.content = content
    }

    /// A group of `content`, already built: `Group(grouping:)` for the
    /// initializers other modules declare in extensions (the table columns'
    /// and table rows', TUIkitTables', and the tabs', TUIkitLists'), which may
    /// not assign `content` themselves, as an initializer in an extension in
    /// another module may not assign a struct's stored properties. A static
    /// function, not a `package` initializer, for the reason the initializer
    /// above is `fileprivate`: a trailing closure could bind to one.
    package static func grouping(_ content: Content) -> Self {
        Self(grouping: content)
    }
}

extension Group: View where Content: View {
    /// Creates a group from the given content.
    ///
    /// - Parameter content: A ``ViewBuilder`` that defines the grouped views.
    public init(@ViewBuilder content: () -> Content) {
        self.init(grouping: content())
    }

    public var body: some View {
        content
    }

    /// Its content's answer: a group's members are laid out as the enclosing
    /// container's own children, so a guide in any of them can be one that
    /// container reports.
    public static var _providesAlignmentGuide: Bool { Content._providesAlignmentGuide }

    /// Its content's answer, as for a guide: the members are the row's.
    public static var _statesSpacingPreference: Bool { Content._statesSpacingPreference }

    /// Its content's answer: a `Group` of several views is those views.
    public static var _handsOverChildren: Bool { Content._handsOverChildren }
}

// MARK: - Equatable Conformance

extension Group: Equatable where Content: View & Equatable {
    public static func == (lhs: Group<Content>, rhs: Group<Content>) -> Bool {
        lhs.content == rhs.content
    }
}

// MARK: - Transparent Child Resolution

// Forwarding child resolution to the content lets a parent stack see the
// grouped views as its own direct children, so `Group` adds no nesting and
// no layout of its own.

extension Group: ChildViewProvider where Content: View {
    public func childViews(context: RenderContext) -> [ChildView] {
        resolveChildViews(from: content, context: context)
    }
}

/// Its content's count: a `ForEach` row that is `Group { a; b }` is two
/// children from every element, which keeps a lazy stack over such rows lazy
/// (`ForEach.rowShape(sectionWholeness:)`, decisions B15).
extension Group: StaticMemberCounting where Content: View {
    package static var staticMemberCount: Int? { TUIkitView.staticMemberCount(Content.self) }

    /// Its content's, as a loop's whole row.
    package static var staticRowMemberCount: Int? { TUIkitView.staticRowMemberCount(Content.self) }
}

/// Its content's count, as SwiftUI counts it: `VStack { Group { G } }` is
/// statically one view, and reports `G`'s edge guides (decisions A-GUIDE-2).
extension Group: StaticViewListCounting where Content: View {
    package static var staticViewListCount: Int? { TUIkitView.staticViewListCount(Content.self) }
}

extension Group: ChildInfoProvider where Content: View {
    public func childInfos(context: RenderContext) -> [ChildInfo] {
        resolveChildInfos(from: content, context: context)
    }
}

// The same transparency for a `List` or a `Section` asking what its content
// IS: flattening alone hands it the rows, but not which `ForEach` made them,
// and that is what keys them by element and carries `.onDelete` / `.onMove`.
extension Group: ListRowsPassThrough where Content: View {
    package var listRowsContent: any View { content }

    package static var listRowsContentTypes: [any View.Type] { [Content.self] }
}

// MARK: - Removal Through a Group

/// `if a { Group { X } }`: the `Group` hands `X` on exactly as it got it, in the
/// scope it was resolved in and with no step of its own, so the `nil` the `if`
/// becomes finds `X`'s departure wherever `X` itself would have been put. A
/// `Group` of several views finds nothing: none of them rendered as its tuple.
extension Group: DepartingSlotAddressing where Content: View {
    package static func departingSlot(
        context: RenderContext, transparentAtScope: Bool
    ) -> ChildView? {
        TUIkitView.departingSlot(
            heldAs: Content.self, context: context, transparentAtScope: transparentAtScope)
    }
}
