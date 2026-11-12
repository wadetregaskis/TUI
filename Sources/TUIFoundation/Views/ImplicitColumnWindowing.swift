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

/// EnvironmentKey for the depth of the identity whose content is a windowing
/// container's column (``EnvironmentValues/implicitColumnWindowingDepth``).
private struct ImplicitColumnWindowingDepthKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// The depth of the identity a windowing container (`GroupBox`,
    /// `DisclosureGroup`, a `Section` drawn as one view) handed its content
    /// to, or `nil` outside one. Only a `ForEach` reached from there by
    /// single-child steps is that container's column
    /// (`ViewIdentity.isDirectDescent(fromDepth:)`): one inside a row of it,
    /// or laid out by a stack in it, is not.
    package var implicitColumnWindowingDepth: Int? {
        get { self[ImplicitColumnWindowingDepthKey.self] }
        set { self[ImplicitColumnWindowingDepthKey.self] = newValue }
    }
}

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

extension RenderContext {
    /// This context with its identity marked as a windowing container's
    /// content: a `ForEach` drawn on its own below it, by single-child steps,
    /// windows its rows past the lazy stack's threshold.
    package func windowingImplicitColumn() -> RenderContext {
        var marked = self
        marked.environment.implicitColumnWindowingDepth = identity.depth
        return marked
    }
}

/// Marks its content as a windowing container's column
/// (``RenderContext/windowingImplicitColumn()``) and draws it at its own
/// identity: no step of its own, so the content's state and focus places are
/// where they were without it.
nonisolated package struct _WindowingImplicitColumn<Content: View>: View, Renderable, Layoutable {
    let content: Content

    package init(_ content: Content) { self.content = content }

    @MainActor package var body: Never {
        fatalError("_WindowingImplicitColumn renders via Renderable")
    }

    @MainActor package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: context.windowingImplicitColumn())
    }

    @MainActor package func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context.windowingImplicitColumn())
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
        guard context.scrollContentOriginDepth != 0, !context.environment.drawsContainerRowsWhole,
            let depth = context.environment.implicitColumnWindowingDepth,
            context.identity.isDirectDescent(fromDepth: depth),
            data(in: context).count > _VStackCore<Self>.anchoredWindowThreshold
        else { return nil }
        return _VStackCore(alignment: .leading, spacing: 0, overflow: .window, content: self)
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
