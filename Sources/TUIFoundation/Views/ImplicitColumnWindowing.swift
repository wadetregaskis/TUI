//  🖥️ TUI — A Terminal UI framework for Swift
//  ImplicitColumnWindowing.swift
//
//  SCROLL-FIT P8 (design §1c, the owner's A-SCROLLFIT-1): the containers that
//  have no lazy counterpart in SwiftUI — `GroupBox`, `DisclosureGroup`, a
//  `Section` drawn as one view — build only the rows on screen once their
//  content passes the lazy stack's threshold, as a `LazyVStack` does. Their
//  content is a column nothing lays out (a `ForEach` drawn on its own stacks
//  its rows, `StackedChildren.swift`); in scroll content, past 256 rows, that
//  column is drawn as a lazy stack is, so the scroll view's request pulls
//  it through the container (`ContainerViewCore+Pulled.swift`, `Section`'s
//  relay) and only the band is built.
//
//  The difference from SwiftUI the owner accepted: a row off screen is not
//  built, so its `onAppear` and `.task` run when it scrolls in, not when the
//  container appears. Below the threshold, and outside scroll content, the
//  column is drawn whole as before.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// A container whose content is a column nothing lays out, and that windows
/// it (`GroupBox`, `DisclosureGroup`, a `Section` drawn as one view): a
/// `ForEach` reached from the container's identity by single-child steps is
/// its column. Read by type from the identity chain, so marking a container
/// writes nothing into the environment its whole subtree would carry.
package protocol WindowsItsImplicitColumn {}

/// EnvironmentKey for ``EnvironmentValues/drawsContainerRowsWhole``.
private struct DrawsContainerRowsWholeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the containers with no lazy counterpart draw every row however
    /// many there are, as before SCROLL-FIT P8: the eager twin a test
    /// compares a windowed container's drawing with. Not an app's option.
    package var drawsContainerRowsWhole: Bool {
        get { self[DrawsContainerRowsWholeKey.self] }
        set { self[DrawsContainerRowsWholeKey.self] = newValue }
    }
}

/// Marks its content as a windowing container's column
/// (``WindowsItsImplicitColumn``): a step of its own type, which a `ForEach`
/// below finds on its identity chain.
nonisolated package struct _WindowingImplicitColumn<Content: View>: View, Renderable, Layoutable,
    WindowsItsImplicitColumn
{
    let content: Content

    package init(_ content: Content) { self.content = content }

    @MainActor package var body: Never {
        fatalError("_WindowingImplicitColumn renders via Renderable")
    }

    @MainActor package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: context.withChildIdentity(type: Self.self))
    }

    @MainActor package func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context.withChildIdentity(type: Self.self))
    }
}

extension _WindowingImplicitColumn: Equatable where Content: Equatable {}

extension View {
    /// This view as a windowing container's column: a `ForEach` that is all
    /// of it builds only the rows on screen past the lazy stack's threshold,
    /// in scroll content (`ImplicitColumnWindowing.swift`).
    nonisolated package func windowingItsRows() -> _WindowingImplicitColumn<Self> {
        _WindowingImplicitColumn(self)
    }
}

@MainActor extension ForEach where Content: View {
    /// The lazy stack this loop is drawn as, when it is a windowing
    /// container's column in scroll content with more rows than a lazy stack
    /// draws whole; `nil` otherwise, and the loop stacks its rows as it always
    /// has. The stack is drawn at this loop's identity, its rows resolved from
    /// it there, so each row keeps the identity it has drawn whole.
    func windowedColumn(context: RenderContext) -> _VStackCore<Self>? {
        guard context.scrollContentOriginDepth != 0,
            data(in: context).count > _VStackCore<Self>.anchoredWindowThreshold,
            Self.isWindowingContainersColumn(context.identity), !context.environment.drawsContainerRowsWhole,
            // A `List` draws a section it cannot read as rows as one view,
            // and keeps its own rows.
            !context.environment.drawsListSectionChrome
        else { return nil }
        return _VStackCore(alignment: .leading, spacing: 0, overflow: .window, content: self)
    }

    /// Whether a windowing container (``WindowsItsImplicitColumn``) stands on
    /// `identity`'s chain, reached by single-child steps: one inside a row of
    /// the column, or laid out by a stack in it, is not its column.
    private static func isWindowingContainersColumn(_ identity: ViewIdentity) -> Bool {
        var cursor: ViewIdentity? = identity
        while let node = cursor {
            if node.leafType.map({ $0 is any WindowsItsImplicitColumn.Type }) == true { return true }
            if node.isSiblingStep { return false }
            cursor = node.parent
        }
        return false
    }

    /// `column` drawn, or, for a measure that draws to find a size (a
    /// `Section` drawn as one view measures so), a blank canvas the size the
    /// column measures: a lazy stack drawn under a measure takes no window, and
    /// would build every row that fits the height it is offered, which for a
    /// measure is all of them.
    func renderWindowed(_ column: _VStackCore<Self>, context: RenderContext) -> FrameBuffer {
        guard context.isMeasuring else { return column.renderToBuffer(context: context) }
        let size = windowedColumnSize(
            column.sizeThatFits(proposal: ProposedViewSize(width: context.availableWidth, height: nil), context: context),
            proposal: ProposedViewSize(width: context.availableWidth, height: nil), context: context)
        return FrameBuffer(emptyWithWidth: size.width, height: min(size.height, max(0, context.availableHeight)))
    }

    /// The windowed column's `size` as the column draws it: the width it is
    /// offered, as a lazy stack's band is drawn. A column drawn whole hugs its
    /// widest row, which only every row measured can say; a sample's widest
    /// would cut a wider row further down, and the widest drawn so far would
    /// widen the container as the page scrolls. Asked its ideal width, it
    /// answers the sample's, as a lazy stack does.
    func windowedColumnSize(_ size: ViewSize, proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        guard proposal.width != nil || !context.asksIdealWidth else { return size }
        return ViewSize(
            width: max(size.width, proposal.width ?? context.availableWidth), height: size.height,
            isWidthFlexible: true, isHeightFlexible: size.isHeightFlexible)
    }
}
