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
    /// whole take. Where none may be a section the column is taken whatever
    /// the loop's count, so they keep them as it crosses the threshold
    /// (O-14 (c), ``TupleView/columnOfSeveral(alignment:spacing:pinning:sectionLoops:in:)``).
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
protocol CountedLoop {
    /// Whether a view of this type is a loop, or an `if` with a loop in a
    /// branch, rather than an `if` of other views: a fact about the type,
    /// the same whatever the data, so the column's step it decides is taken
    /// or not whatever the loop's count
    /// (``TupleView/columnOfSeveral(alignment:spacing:pinning:sectionLoops:in:)``).
    static var mayBeLoop: Bool { get }

    func liveElementCount(in context: RenderContext) -> Int
}

@MainActor extension ForEach: CountedLoop where Content: View {
    static var mayBeLoop: Bool { true }

    func liveElementCount(in context: RenderContext) -> Int { data(in: context).count }
}

/// ``CountedLoop/mayBeLoop`` of `type`: `false` for a view that is no loop.
@MainActor
func viewMayBeLoop(_ type: Any.Type) -> Bool {
    (type as? any CountedLoop.Type)?.mayBeLoop ?? false
}

/// Whether `content`, a section's, is a loop (written bare or in an `if`)
/// that a lazy stack's own section draws as a lazy stack of its own, in
/// scroll content: one past the lazy stack's threshold, as a windowing
/// container's column is (``ForEach/windowedColumn(context:)``), or any,
/// `whateverItsCount`, in a stack whose sections' loops together pass it
/// (``PinnedSectionScope/windowsSectionLoops``). Counted without building a
/// row.
@MainActor
func sectionContentLoopWindows<Content: View>(
    _ content: Content, whateverItsCount: Bool, in context: RenderContext
) -> Bool {
    guard context.scrollContentOriginDepth != 0, let loop = content as? any CountedLoop,
        !context.environment.drawsContainerRowsWhole, !context.environment.drawsListSectionChrome
    else { return false }
    return whateverItsCount || loop.liveElementCount(in: context) > _VStackCore<EmptyView>.anchoredWindowThreshold
}

// MARK: - The rows a stack's sections' loops make

/// Views that may be or make sections: the rows they hand a lazy stack,
/// each section's loop counted by its elements, so a stack of a few sections
/// can tell whether their rows together pass its threshold
/// (``PinnedSectionScope/windowsSectionLoops``) without building a row.
@MainActor
protocol SectionLoopRowsCounting {
    /// The rows, counting a section as its loop's elements and one more, and
    /// any other view as one — stopping once past `limit` — or `nil` when no
    /// section with a loop is among them.
    func sectionLoopRows(upTo limit: Int, in context: RenderContext) -> Int?

    /// Whether ``sectionLoopRows(upTo:in:)`` may pass the lazy stack's
    /// threshold for some data: a section whose content is a loop, a loop of
    /// sections, or views holding one. A fact about the type, so what it
    /// decides does not come and go with the data
    /// (``TupleView/columnOfSeveral(alignment:spacing:pinning:sectionLoops:in:)``).
    var mayCountSectionLoops: Bool { get }
}

@MainActor extension Section: SectionLoopRowsCounting where Parent: View, Content: View, Footer: View {
    var mayCountSectionLoops: Bool { viewMayBeLoop(Content.self) }

    func sectionLoopRows(upTo limit: Int, in context: RenderContext) -> Int? {
        guard showsContent, let loop = content as? any CountedLoop else { return nil }
        return 1 + loop.liveElementCount(in: context)
    }
}

@MainActor extension ForEach: SectionLoopRowsCounting where Content: View {
    var mayCountSectionLoops: Bool { Content.self is any SectionLoopRowsCounting.Type }

    /// A loop of sections: each element's section built, its rows counted —
    /// a section value, not one of its rows. Of anything else, `nil`, with
    /// nothing built; and of more sections than `limit`, which a lazy stack
    /// windows by their count, sampling each section it measures whole (the
    /// SCROLL-FIT design's S7 record says why that stays).
    func sectionLoopRows(upTo limit: Int, in context: RenderContext) -> Int? {
        guard Content.self is any SectionLoopRowsCounting.Type else { return nil }
        let data = data(in: context)
        guard data.count <= limit else { return nil }
        var total = 0
        var sawSection = false
        for element in data {
            guard let rows = (content(element) as? any SectionLoopRowsCounting)?.sectionLoopRows(
                upTo: limit - total, in: context)
            else {
                total += 1
                continue
            }
            sawSection = true
            total += rows
            if total > limit { break }
        }
        return sawSection ? total : nil
    }
}

@MainActor extension TupleView: SectionLoopRowsCounting {
    var mayCountSectionLoops: Bool {
        var may = false
        for child in repeat each children {
            may = may || (child as? any SectionLoopRowsCounting)?.mayCountSectionLoops == true
        }
        return may
    }

    func sectionLoopRows(upTo limit: Int, in context: RenderContext) -> Int? {
        var total = 0
        var sawSection = false
        for child in repeat each children {
            guard total <= limit else { break }
            if let rows = (child as? any SectionLoopRowsCounting)?.sectionLoopRows(upTo: limit - total, in: context) {
                sawSection = true
                total += rows
            } else {
                total += 1
            }
        }
        return sawSection ? total : nil
    }
}

@MainActor extension ConditionalView: CountedLoop {
    static var mayBeLoop: Bool { viewMayBeLoop(TrueContent.self) || viewMayBeLoop(FalseContent.self) }

    func liveElementCount(in context: RenderContext) -> Int {
        switch self {
        case .trueContent(let content): (content as? any CountedLoop)?.liveElementCount(in: context) ?? 0
        case .falseContent(let content): (content as? any CountedLoop)?.liveElementCount(in: context) ?? 0
        }
    }
}

@MainActor extension Optional: CountedLoop where Wrapped: View {
    static var mayBeLoop: Bool { viewMayBeLoop(Wrapped.self) }

    func liveElementCount(in context: RenderContext) -> Int {
        guard case .some(let view) = self, let loop = view as? any CountedLoop else { return 0 }
        return loop.liveElementCount(in: context)
    }
}

@MainActor extension TupleView: ImplicitColumnMembers {
    package func columnOfSeveral(in context: RenderContext) -> (any View)? {
        columnOfSeveral(alignment: .leading, spacing: 0, pinning: false, sectionLoops: false, in: context)
    }

    /// These views as a column laid out at `alignment` and `spacing`, when
    /// one is a loop, whatever its count. `nil` otherwise; and, `pinning` (the
    /// loop's lazy stack pins its sections) or `sectionLoops` (the stack's
    /// sections' loops together pass the lazy stack's threshold,
    /// ``PinnedSectionScope/windowsSectionLoops``), `nil` too when a view
    /// beside the loop may be a section, which the column would neither pin
    /// nor keep whole; and, where such a section's own loop may pass the
    /// threshold (``SectionLoopRowsCounting/mayCountSectionLoops``), which the
    /// stack decides by the count, `nil` while the loop is within it.
    ///
    /// The column is a step of identity (``_ImplicitColumnOfSeveral``): its
    /// views, and the loop's rows, are addressed under it, not where the
    /// views stacked whole are. Taken only past the threshold, it came and
    /// went as a filtered loop crossed it, both ways, and every one of these
    /// views — a filter field beside the loop, with its focus — and every row
    /// started afresh at each crossing (H-71). So it is taken whatever the
    /// count (the owner's O-14 (c), 2026-11-21): one change of identity, when
    /// an app first runs on this, and none after. A loop at or below the
    /// threshold is drawn under the step as it was drawn without it: a lazy
    /// stack's as a lazy stack of its own
    /// (``_VStackCore/implicitColumn(of:context:rowCount:isContainersColumn:)``),
    /// a windowing container's stacked whole (`ForEach.staysWhole(in:)`).
    ///
    /// So also where the stack pins — the loop's lazy stack pins the
    /// sections the loop makes, in the same lines — and where a section
    /// beside the loop is taken apart, as the column takes it apart as the
    /// stack does; and where the scroll view reads its rows back or the stack
    /// is marked `scrollTargetLayout()`: the column reports its loop's rows
    /// one by one, as the flat stack does (`StackPulledColumn+LoopRows.swift`).
    /// Kept at the threshold, and so still reset crossing it: a section
    /// beside the loop that may hold a long loop of its own, unpinned (pinned,
    /// the column is not taken at any count).
    package func columnOfSeveral(
        alignment: HorizontalAlignment, spacing: Int, pinning: Bool, sectionLoops: Bool, in context: RenderContext
    ) -> (any View)? {
        var loop: (any CountedLoop)?
        var sectionBeside = false
        for child in repeat each children {
            if loop == nil, let counted = child as? any CountedLoop, type(of: counted).mayBeLoop {
                loop = counted
            } else if TUIFoundation.mayHandOver(.section, type(of: child)) {
                sectionBeside = true
            }
        }
        guard let loop else { return nil }
        if sectionBeside {
            guard !pinning, !sectionLoops else { return nil }
            // Unpinned, a section beside the loop is taken apart by the
            // column as by the stack, unless its own loop is long enough for
            // the stack to keep it whole, which the stack decides by the
            // count: where it may be, the column keeps the threshold.
            if mayCountSectionLoops,
                loop.liveElementCount(in: context) <= _VStackCore<EmptyView>.anchoredWindowThreshold
            {
                return nil
            }
        }
        return _VStackCore(alignment: alignment, spacing: spacing, overflow: .clip, content: self)
    }
}

// MARK: - A lazy stack's column of several

/// A lazy stack's content of several views that may be drawn as a column of
/// them, the loop among them drawn as a lazy stack of its own: a builder's
/// tuple.
@MainActor
package protocol LazyColumnMembers {
    /// See ``TupleView/columnOfSeveral(alignment:spacing:pinning:sectionLoops:in:)``.
    func columnOfSeveral(
        alignment: HorizontalAlignment, spacing: Int, pinning: Bool, sectionLoops: Bool, in context: RenderContext
    ) -> (any View)?
}

extension TupleView: LazyColumnMembers {}

/// The alignment and spacing a loop drawn as a column of several's lazy stack
/// lays its rows out at, and the sections' headers and footers it pins: those
/// of the lazy stack the column stands in for
/// (``_VStackCore/lazyColumnOfSeveral(context:)``). A windowing container's
/// column (a `GroupBox`'s) states none, and its rows are leading, with no
/// spacing and nothing pinned, as its content drawn whole stacks them.
package struct ImplicitColumnRowLayout: Equatable, Sendable {
    let alignment: HorizontalAlignment
    let spacing: Int
    var pinnedViews: PinnedScrollableViews = []
    /// Whether the loop's lazy stack prices its rows by a sample however few
    /// its elements (`_VStackCore.estimatesWhateverItsCount`): a section's, in
    /// a lazy stack whose sections' loops together pass the threshold
    /// (``PinnedSectionScope/windowsSectionLoops``). Unset, a loop at or below
    /// the threshold is still drawn as a lazy stack under the column, which
    /// draws every row of so few — unless ``takesFewApart``.
    var windowsAnyCount = false
    /// Whether a loop the column would draw as a lazy stack that draws every
    /// row — at or below the threshold, ``windowsAnyCount`` unset — is taken
    /// apart into the column's own rows instead (`ForEach.staysWhole(in:)`):
    /// a section's column of its parts (`_SectionCore.pulledPartsColumn`).
    /// The rows have the same identities either way, resolved under the
    /// loop's step, so nothing changes as the loop crosses the threshold;
    /// taken apart, the column lays them out in its own walk, as the section
    /// laid out whole did, where the lazy stack's exact walk over a few rows
    /// cost a small stack of sections 13 to 23% a frame (H71-SECTIONS).
    var takesFewApart = false
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

/// EnvironmentKey for ``EnvironmentValues/implicitColumnDrawnAt``.
private struct ImplicitColumnDrawnAtKey: EnvironmentKey {
    static let defaultValue: ViewIdentity? = nil
}

extension EnvironmentValues {
    /// The identity a column nothing lays out is being drawn at as a lazy
    /// stack (``_VStackCore/renderAsImplicitColumn(context:)``): the loop's
    /// own, so the stack resolving its rows there asks the loop at the step
    /// it stands at among a column of several, and the loop must not answer
    /// that it stays whole (`ForEach.staysWhole(in:)`), or the stack's one
    /// row would be the loop, stacked whole.
    package var implicitColumnDrawnAt: ViewIdentity? {
        get { self[ImplicitColumnDrawnAtKey.self] }
        set { self[ImplicitColumnDrawnAtKey.self] = newValue }
    }
}

extension RenderContext {
    /// This context for the lazy stack a column nothing lays out is drawn as:
    /// no ``EnvironmentValues/implicitColumnRowLayout``, and the column's
    /// identity noted (``EnvironmentValues/implicitColumnDrawnAt``).
    func drawingImplicitColumn() -> RenderContext {
        var context = leavingImplicitColumnRowLayout()
        if context.environment.implicitColumnDrawnAt != context.identity {
            context.environment.implicitColumnDrawnAt = context.identity
        }
        return context
    }

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
    /// after it, still walked).
    ///
    /// A stack that pins its sections' headers or footers (`pinnedViews:`)
    /// hands its pins to the loop's lazy stack, so the sections a loop makes
    /// pin there as they pinned in it: a section is pinned within its own
    /// lines, which are the same lines in either. Not where a view beside the
    /// loop may be a section (``mayHandOver(_:_:)``): the column, an eager
    /// stack, would not pin it, and the stack draws as before (63,300 rows on
    /// the first frame for a title and 300 sections of 30, where a pinning
    /// stack of a title and a loop now builds a screenful).
    ///
    /// The rows' identities are the column's, not those the rows had taken
    /// apart. The column is taken whatever the loop's count, so they keep
    /// them as it crosses the threshold (O-14 (c)) — pinned or not, marked
    /// `scrollTargetLayout()` or not, its rows read back or not — except
    /// where a section beside the loop may hold a long loop of its own
    /// (``TupleView/columnOfSeveral(alignment:spacing:pinning:sectionLoops:in:)``),
    /// whose rows start afresh at each crossing.
    @MainActor func lazyColumnOfSeveral(context: RenderContext) -> (column: any View, context: RenderContext)? {
        let pins = pinsSectionHeaders || pinsSectionFooters
        guard overflow == .window, context.scrollContentOriginDepth != 0,
            let members = content as? any LazyColumnMembers,
            !context.environment.drawsContainerRowsWhole, !context.environment.drawsListSectionChrome
        else { return nil }
        // A title over a loop of a few long sections, `LazyVStack { title;
        // ForEach(groups) { Section … } }`: the loop drawn as a lazy stack of
        // its own however few its sections, each drawing its loop so
        // (``PinnedSectionScope/windowsSectionLoops``).
        let sectionLoops = contentMayHoldSections && sectionLoopsPassThreshold(context)
        guard
            let column = members.columnOfSeveral(
                alignment: alignment, spacing: spacing, pinning: pins, sectionLoops: sectionLoops, in: context)
        else { return nil }
        var columnContext = context.withChildIdentity(type: _ImplicitColumnOfSeveral.self)
        var pinned: PinnedScrollableViews = []
        if pinsSectionHeaders { pinned.insert(.sectionHeaders) }
        if pinsSectionFooters { pinned.insert(.sectionFooters) }
        columnContext.environment.implicitColumnRowLayout = ImplicitColumnRowLayout(
            alignment: alignment, spacing: spacing, pinnedViews: pinned, windowsAnyCount: sectionLoops)
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
        .implicitColumn(
            of: self, context: context, rowCount: data(in: context).count,
            isContainersColumn: Self.isWindowingContainersColumn(context.identity))
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
    /// the column's views; so is a loop the column's own loop draws, as the
    /// content of the lazy stack drawn at that loop's step: only `node`
    /// itself may be a loop, and every step above it an `if`.
    private static func isAmongColumnOfSeveral(_ node: ViewIdentity) -> Bool {
        var cursor: ViewIdentity? = node
        var isNode = true
        while let step = cursor {
            if let type = step.leafType {
                if ObjectIdentifier(type) == ObjectIdentifier(_ImplicitColumnOfSeveral.self) { return true }
                guard isNode ? type is any CountedLoop.Type : type is any IfContent.Type else { return false }
            } else if !step.isBranchStep {
                return false
            }
            isNode = false
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
    ///
    /// Whatever its count (O-14 (c)): the column is taken for a loop of any
    /// count, and the rows are this loop's whether it draws them as a lazy
    /// stack or stacked whole, so they keep their identities as the count
    /// crosses the threshold. Taken apart below it, they were the column's.
    /// Not where the lazy stack it is drawn as resolves its rows, at the same
    /// identity (`implicitColumnDrawnAt`): its rows are
    /// that stack's.
    ///
    /// Nor, in a section's column of its parts, where the lazy stack would
    /// draw every row (`ImplicitColumnRowLayout.takesFewApart`): the column
    /// takes the rows as its own, under the same identities.
    public func staysWhole(in context: RenderContext) -> Bool {
        guard context.scrollContentOriginDepth != 0, Self.isAmongColumnOfSeveral(context.identity),
            context.environment.implicitColumnDrawnAt != context.identity
        else { return false }
        guard let layout = context.environment.implicitColumnRowLayout, layout.takesFewApart, !layout.windowsAnyCount
        else { return true }
        return data(in: context).count > _VStackCore<EmptyView>.anchoredWindowThreshold
    }
}

extension _VStackCore {
    /// The lazy stack a column nothing lays out is drawn as — a windowing
    /// container's loop (`ForEach.windowedColumn`), or any other view of rows
    /// drawn on its own — in scroll content, when its `rowCount` rows are more
    /// than a lazy stack draws whole, or, under a lazy stack's column of
    /// several, however few; `nil` otherwise, and the column is stacked
    /// whole. At the alignment, spacing and pins of the lazy stack a column
    /// of several stands in for (``lazyColumnOfSeveral(context:)``),
    /// else leading, with no spacing and nothing pinned, as the column drawn
    /// whole stacks its rows. Shared, and `package`, so a view of rows in
    /// another module windows exactly as a loop does.
    @MainActor package static func implicitColumn(
        of content: Content, context: RenderContext, rowCount: @autoclosure () -> Int,
        isContainersColumn: @autoclosure () -> Bool = true
    ) -> Self? {
        let layout = context.environment.implicitColumnRowLayout
        // Under a lazy stack's column of several (`layout` stated), the loop
        // is drawn as a lazy stack of its own whatever its count: the column
        // is taken whatever the count (O-14 (c)), and a lazy stack draws a
        // few rows as the stack the column stands in drew them.
        guard context.scrollContentOriginDepth != 0, layout != nil || rowCount() > anchoredWindowThreshold,
            isContainersColumn(), !context.environment.drawsContainerRowsWhole,
            // A `List` draws a section it cannot read as rows as one view,
            // and keeps its own rows.
            !context.environment.drawsListSectionChrome
        else { return nil }
        return Self(
            alignment: layout?.alignment ?? .leading, spacing: layout?.spacing ?? 0, overflow: .window,
            pinnedViews: layout?.pinnedViews ?? [], estimatesWhateverItsCount: layout?.windowsAnyCount ?? false,
            content: content)
    }

    /// This stack drawn as the column ``implicitColumn(of:context:rowCount:isContainersColumn:)``
    /// made it — or, for a measure that draws to find a size (a `Section`
    /// drawn as one view measures so), a blank canvas the size the column
    /// measures: a lazy stack drawn under a measure takes no window, and would
    /// build every row that fits the height it is offered, which for a measure
    /// is all of them.
    @MainActor package func renderAsImplicitColumn(context: RenderContext) -> FrameBuffer {
        let context = context.drawingImplicitColumn()
        Self.fileImplicitColumn(context: context)
        guard context.isMeasuring else { return renderToBuffer(context: context) }
        let proposal = ProposedViewSize(width: context.availableWidth, height: nil)
        let size = implicitColumnSize(sizeThatFits(proposal: proposal, context: context), proposal: proposal, context: context)
        return FrameBuffer(emptyWithWidth: size.width, height: min(size.height, max(0, context.availableHeight)))
    }

    /// The size ``renderAsImplicitColumn(context:)`` draws at.
    @MainActor package func sizeAsImplicitColumn(proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        let context = context.drawingImplicitColumn()
        Self.fileImplicitColumn(context: context)
        return implicitColumnSize(sizeThatFits(proposal: proposal, context: context), proposal: proposal, context: context)
    }

    /// Files the lazy stack drawn at the column's own identity as one that
    /// places its rows against a request (``PullConsumers/noteLayout(_:places:)``),
    /// before they are measured: they are siblings at the column's identity,
    /// whose type is no pulling container's, so a lazy stack in a row — a
    /// section's loop, its section drawn as a column of its parts — is
    /// pulled where it stands (`isPulledWhereItStands`) as a row of a lazy
    /// stack written out is. Unfiled, the rows were drawn whole, every row of
    /// each section in the band built (210 a page for a title over 300
    /// sections of 30).
    @MainActor private static func fileImplicitColumn(context: RenderContext) {
        guard context.scrollContentOriginDepth != 0 else { return }
        context.renderCache?.pullConsumers.noteLayout(context.identity, places: true)
    }

    /// The column's `size` as the column draws it: the width it is offered,
    /// as a lazy stack's band is drawn. A column drawn whole hugs its widest
    /// row, which only every row measured can say; a sample's widest would
    /// cut a wider row further down, and the widest drawn so far would widen
    /// the container as the page scrolls. Asked its ideal width, it answers
    /// the sample's, as a lazy stack does.
    private func implicitColumnSize(_ size: ViewSize, proposal: ProposedViewSize, context: RenderContext) -> ViewSize {
        guard proposal.width != nil || !context.asksIdealWidth else { return size }
        return ViewSize(
            width: max(size.width, proposal.width ?? context.availableWidth), height: size.height,
            isWidthFlexible: true, isHeightFlexible: size.isHeightFlexible)
    }
}
