//  🖥️ TUI — A Terminal UI framework for Swift
//  OutlineGroup+Drawn.swift
//
//  An outline drawn on its own, where nothing above resolved its rows into
//  siblings: a scroll view's whole content (the shape the type's own doc
//  example uses), a container's column, a view's entire body. Its `body`
//  stacks its rows (`_OutlineGroupCore`), as a `ForEach` drawn on its own
//  does; before this its `body` was `Never` and it drew nothing at all, the
//  renderer falling through to an empty buffer, so
//  `ScrollView { OutlineGroup(…) }` drew a blank screen.
//
//  In scroll content, past the lazy stack's threshold, the rows are drawn as a
//  lazy stack draws them, so only those on screen are built: an outline has no
//  lazy counterpart in SwiftUI, which is where the owner's A-SCROLLFIT-1 has a
//  container window its rows, as `GroupBox` and `DisclosureGroup` do
//  (`ImplicitColumnWindowing.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

// MARK: - The rows, built as they are asked for

@MainActor extension OutlineGroup: LazyChildViewProvider where Leaf: View {
    /// The rows as an on-demand collection: the count and each row's key come
    /// from the visible nodes, which are kept from pass to pass while the tree
    /// and its open branches are the same (`OutlineVisibleNodes`), and a
    /// row view is built only when a container asks for that row — so a lazy
    /// stack of a large open tree builds about a screenful.
    public func childViewCollection(context: RenderContext) -> ChildViewCollection {
        let expansion = expansion(context: context)
        let nodes = visibleNodes(context: context, expansion: expansion).nodes
        return ChildViewCollection(
            count: nodes.count,
            key: { identityKey(nodes[$0].id) },
            anyID: { AnyHashable(nodes[$0].id) },
            build: { child(for: nodes[$0], expansion: expansion) })
    }

    /// One node's child, keyed by the node's id: the single constructor behind
    /// the eager array and the lazy collection, so the two cannot drift.
    func child(for node: Node, expansion: OutlineExpansion<ID>) -> ChildView {
        ChildView(
            row(for: node, expansion: expansion),
            identityType: _OutlineRow<Data.Element, ID, Leaf>.self,
            key: identityKey(node.id))
    }
}

// MARK: - Drawn on its own

/// An outline's rows drawn where nothing lays them out: `OutlineGroup`'s
/// body. It stacks the visible nodes' rows, or, in scroll content past the
/// lazy stack's threshold, draws them as a lazy stack does
/// (``windowedColumn(context:)``). Nothing looks for this type: a container
/// that takes an outline apart does so from the `OutlineGroup` itself, so this
/// is reached only by drawing the outline as one view.
struct _OutlineGroupCore<Data: RandomAccessCollection, ID: Hashable, Leaf: View>: View, Renderable, Layoutable {
    let outline: OutlineGroup<Data, ID, Leaf>

    var body: Never {
        fatalError("_OutlineGroupCore renders via Renderable")
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        if let column = windowedColumn(context: context) {
            return column.renderAsImplicitColumn(context: context)
        }
        return renderStackedVertically(outline.childViews(context: context), context: context)
    }

    func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        if let column = windowedColumn(context: context) {
            return column.sizeAsImplicitColumn(proposal: proposal, context: context)
        }
        return measureStackedVertically(outline.childViews(context: context), proposal: proposal, context: context)
    }

    /// The lazy stack the rows are drawn as, in scroll content with more open
    /// rows than a lazy stack draws whole; `nil` otherwise, and the rows are
    /// stacked whole. Drawn at this core's identity, its rows resolved from
    /// the outline there, so each row keeps the identity it has drawn whole,
    /// and the expansion is the same set either way.
    ///
    /// Unlike a `ForEach`, which windows only as a windowing container's
    /// column (`ScrollView { ForEach }` is SwiftUI's eager implicit stack),
    /// an outline windows wherever it is drawn on its own in scroll content:
    /// it is the container, and it has no lazy counterpart.
    private func windowedColumn(context: RenderContext) -> _VStackCore<OutlineGroup<Data, ID, Leaf>>? {
        .implicitColumn(
            of: outline, context: context,
            rowCount: outline.visibleNodes(context: context, expansion: outline.expansion(context: context))
                .nodes.count)
    }
}
