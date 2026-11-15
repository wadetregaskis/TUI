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
//  relay) and only the band is built. Content of several views with such a
//  loop among them — `GroupBox { header; ForEach(rows) }` — is drawn as a
//  column of those views, the loop one of them, drawn as the lazy stack.
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
        let column = context.withChildIdentity(type: Self.self).leavingImplicitColumnRowLayout()
        if let several = columnOfSeveral(context: column) {
            return TUIView.renderToBuffer(several, context: column.withChildIdentity(type: _ImplicitColumnOfSeveral.self))
        }
        return TUIView.renderToBuffer(content, context: column)
    }

    @MainActor package func sizeThatFits(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        let column = context.withChildIdentity(type: Self.self).leavingImplicitColumnRowLayout()
        if let several = columnOfSeveral(context: column) {
            return measureChild(
                several, proposal: proposal, context: column.withChildIdentity(type: _ImplicitColumnOfSeveral.self))
        }
        return measureChild(content, proposal: proposal, context: column)
    }

    /// The content as a column that pulls its views, when it is several of
    /// them and one is a loop past the lazy stack's threshold, in scroll
    /// content: `GroupBox { header; ForEach(rows) }`. Its views are the
    /// column's children, at its step (``_ImplicitColumnOfSeveral``), and the
    /// loop among them stays one child (`ForEach.staysWhole(in:)`), drawn as
    /// the lazy stack it is drawn as alone; so the header is drawn whole and
    /// only the loop's rows on screen are built. `nil` otherwise, and the
    /// content draws as it always has: several views stacked whole, which
    /// builds every row of the loop to resolve them.
    ///
    /// The views' identities are the column's, not those the views stacked
    /// whole take, so a loop growing past the threshold starts its rows' state
    /// afresh, once.
    @MainActor private func columnOfSeveral(context: RenderContext) -> (any View)? {
        guard context.scrollContentOriginDepth != 0, !context.environment.drawsContainerRowsWhole,
            !context.environment.drawsListSectionChrome
        else { return nil }
        return (content as? any ImplicitColumnMembers)?.columnOfSeveral(in: context)
    }
}

/// The identity step a windowing container's column of several views is
/// drawn at as a column (`_WindowingImplicitColumn.columnOfSeveral`): its
/// views are sibling steps under it, so the column is a container a pulled
/// view stands in (``ScrollPlacing``), and a loop directly under it is the
/// container's column, drawn as a lazy stack (`ForEach.windowedColumn`).
package enum _ImplicitColumnOfSeveral: ScrollPlacing {}

/// A windowing container's content that may be several views, one of them a
/// loop past the lazy stack's threshold: a builder's tuple, or the erasures a
/// style's configuration holds it in.
@MainActor
package protocol ImplicitColumnMembers {
    /// These views as a column that pulls them, when one is such a loop
    /// (written bare, or in an `if`); `nil` otherwise.
    func columnOfSeveral(in context: RenderContext) -> (any View)?
}

/// What an `if` is in a view builder: the conditional an `if`/`else` makes,
/// or the `Optional` an `if` alone does.
private protocol IfContent {}
extension ConditionalView: IfContent {}
extension Optional: IfContent where Wrapped: View {}

/// A view that is, or holds as an `if` does, a loop: counted without
/// building a row.
@MainActor
private protocol CountedLoop {
    func liveElementCount(in context: RenderContext) -> Int
}

@MainActor extension ForEach: CountedLoop where Content: View {
    fileprivate func liveElementCount(in context: RenderContext) -> Int { data(in: context).count }
}

@MainActor extension ConditionalView: CountedLoop {
    fileprivate func liveElementCount(in context: RenderContext) -> Int {
        switch self {
        case .trueContent(let content): (content as? any CountedLoop)?.liveElementCount(in: context) ?? 0
        case .falseContent(let content): (content as? any CountedLoop)?.liveElementCount(in: context) ?? 0
        }
    }
}

@MainActor extension Optional: CountedLoop where Wrapped: View {
    fileprivate func liveElementCount(in context: RenderContext) -> Int {
        guard case .some(let view) = self, let loop = view as? any CountedLoop else { return 0 }
        return loop.liveElementCount(in: context)
    }
}

@MainActor extension TupleView: ImplicitColumnMembers {
    package func columnOfSeveral(in context: RenderContext) -> (any View)? {
        columnOfSeveral(alignment: .leading, spacing: 0, in: context)
    }

    /// These views as a column laid out at `alignment` and `spacing`, when
    /// one is a loop past the lazy stack's threshold; `nil` otherwise.
    package func columnOfSeveral(alignment: HorizontalAlignment, spacing: Int, in context: RenderContext) -> (any View)? {
        for child in repeat each children {
            if let loop = child as? any CountedLoop,
                loop.liveElementCount(in: context) > _VStackCore<EmptyView>.anchoredWindowThreshold
            {
                return _VStackCore(alignment: alignment, spacing: spacing, overflow: .clip, content: self)
            }
        }
        return nil
    }
}

// MARK: - A lazy stack's column of several

/// A lazy stack's content of several views that may be drawn as a column of
/// them, the loop among them drawn as a lazy stack of its own: a builder's
/// tuple.
@MainActor
package protocol LazyColumnMembers {
    /// See ``TupleView/columnOfSeveral(alignment:spacing:in:)``.
    func columnOfSeveral(alignment: HorizontalAlignment, spacing: Int, in context: RenderContext) -> (any View)?
}

extension TupleView: LazyColumnMembers {}

/// The alignment and spacing a loop drawn as a column of several's lazy stack
/// lays its rows out at: those of the lazy stack the column stands in for
/// (``_VStackCore/lazyColumnOfSeveral(context:)``). A windowing container's
/// column (a `GroupBox`'s) states none, and its rows are leading, with no
/// spacing, as its content drawn whole stacks them.
package struct ImplicitColumnRowLayout: Equatable, Sendable {
    let alignment: HorizontalAlignment
    let spacing: Int
}

/// EnvironmentKey for ``EnvironmentValues/implicitColumnRowLayout``.
private struct ImplicitColumnRowLayoutKey: EnvironmentKey {
    static let defaultValue: ImplicitColumnRowLayout? = nil
}

extension EnvironmentValues {
    /// See ``ImplicitColumnRowLayout``. Set on a lazy stack's column of
    /// several, and cleared under the loop drawn there and under a windowing
    /// container's column, so no column further down reads it.
    package var implicitColumnRowLayout: ImplicitColumnRowLayout? {
        get { self[ImplicitColumnRowLayoutKey.self] }
        set { self[ImplicitColumnRowLayoutKey.self] = newValue }
    }
}

extension RenderContext {
    /// This context with no ``EnvironmentValues/implicitColumnRowLayout``,
    /// written only where one was set.
    func leavingImplicitColumnRowLayout() -> RenderContext {
        guard environment.implicitColumnRowLayout != nil else { return self }
        var context = self
        context.environment.implicitColumnRowLayout = nil
        return context
    }
}

extension _VStackCore {
    /// A lazy stack whose content is several views, one of them a loop past
    /// the threshold, in scroll content — `LazyVStack { header; ForEach(rows)
    /// }` — as the column of those views a windowing container's content of
    /// several is drawn as (`_WindowingImplicitColumn.columnOfSeveral`): the
    /// header drawn whole, the loop a lazy stack of its own at this stack's
    /// alignment and spacing, a pulled child of the column. `nil` otherwise,
    /// and the stack draws as before.
    ///
    /// Taken apart into one column of rows, the tuple resolved its loop
    /// eagerly, building every row on the first frame for each measure of it
    /// (30,035 at 10,000 rows, 30 × 12; the row memo then served every row
    /// after it, still walked). Not for a stack that pins its sections, which
    /// pins only its own.
    ///
    /// The rows' identities are the column's, not those the rows had taken
    /// apart, so a loop growing past the threshold starts its rows' state
    /// afresh, once, as a `GroupBox`'s does.
    @MainActor func lazyColumnOfSeveral(context: RenderContext) -> (column: any View, context: RenderContext)? {
        guard overflow == .window, !pinsSectionHeaders, !pinsSectionFooters, context.scrollContentOriginDepth != 0,
            let members = content as? any LazyColumnMembers,
            !context.environment.drawsContainerRowsWhole, !context.environment.drawsListSectionChrome,
            let column = members.columnOfSeveral(alignment: alignment, spacing: spacing, in: context)
        else { return nil }
        var columnContext = context.withChildIdentity(type: _ImplicitColumnOfSeveral.self)
        columnContext.environment.implicitColumnRowLayout = ImplicitColumnRowLayout(alignment: alignment, spacing: spacing)
        return (column, columnContext)
    }
}

@MainActor extension _StyledContent: ImplicitColumnMembers {
    package func columnOfSeveral(in context: RenderContext) -> (any View)? {
        (underlying as? any ImplicitColumnMembers)?.columnOfSeveral(in: context)
    }
}

@MainActor extension AnyView: ImplicitColumnMembers {
    package func columnOfSeveral(in context: RenderContext) -> (any View)? {
        (erasedView as? any ImplicitColumnMembers)?.columnOfSeveral(in: context)
    }
}

@MainActor extension DisclosureGroupStyleConfiguration.Content: ImplicitColumnMembers {
    package func columnOfSeveral(in context: RenderContext) -> (any View)? {
        make().columnOfSeveral(in: context)
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
        // The lazy stack's own alignment and spacing, where the column of
        // several stands in for one (`_VStackCore.lazyColumnOfSeveral`).
        let layout = context.environment.implicitColumnRowLayout
        return _VStackCore(
            alignment: layout?.alignment ?? .leading, spacing: layout?.spacing ?? 0, overflow: .window, content: self)
    }

    /// Whether a windowing container (``WindowsItsImplicitColumn``) stands on
    /// `identity`'s chain, reached by single-child steps: one inside a row of
    /// the column, or laid out by a stack in it, is not its column.
    private static func isWindowingContainersColumn(_ identity: ViewIdentity) -> Bool {
        var cursor: ViewIdentity? = identity
        while let node = cursor {
            if node.leafType.map({ $0 is any WindowsItsImplicitColumn.Type }) == true { return true }
            // One of several views a windowing container draws as a column
            // (``_ImplicitColumnOfSeveral``), written bare or in an `if`, is
            // the container's column too.
            if node.isSiblingStep { return isAmongColumnOfSeveral(node) }
            cursor = node.parent
        }
        return false
    }

    /// Whether `node`, a sibling step, is one of the views of a column of
    /// several (``_ImplicitColumnOfSeveral``): its parent is the column's
    /// step, or an `if` among the column's views — the branch an `if`/`else`
    /// took, and the conditional or the `Optional` above it — stands between.
    /// A loop a stack in the column lays out is that stack's rows, not one of
    /// the column's views.
    private static func isAmongColumnOfSeveral(_ node: ViewIdentity) -> Bool {
        var cursor: ViewIdentity? = node
        while let step = cursor {
            if let type = step.leafType {
                if ObjectIdentifier(type) == ObjectIdentifier(_ImplicitColumnOfSeveral.self) { return true }
                guard type is any CountedLoop.Type else { return false }
            } else if !step.isBranchStep {
                return false
            }
            cursor = step.parent
        }
        return false
    }

    /// A loop drawn as a windowing container's column stays one child of the
    /// column of several views it stands in (`_ImplicitColumnOfSeveral`),
    /// drawn as its lazy stack, rather than handing the column every row.
    /// Asked where it is resolved: at its own step among the column's views,
    /// or an `if`'s among them. Anywhere else — a stack it is the content of —
    /// it is taken apart as always.
    public func staysWhole(in context: RenderContext) -> Bool {
        context.scrollContentOriginDepth != 0 && Self.isAmongColumnOfSeveral(context.identity)
            && windowedColumn(context: context) != nil
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
