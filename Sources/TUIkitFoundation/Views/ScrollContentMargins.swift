//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollContentMargins.swift
//
//  `contentMargins`: space a scroll view keeps around its content, inside the
//  scrollable area — so it scrolls with the content — and, optionally, around
//  its scroll indicators.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - Placement

/// Which part of a view a content margin applies to. Matches SwiftUI's
/// `ContentMarginPlacement`.
///
/// ```swift
/// ScrollView(.horizontal) { … }
///     .contentMargins(.horizontal, 2)                    // content and indicators
///     .contentMargins(.vertical, 1, for: .scrollContent) // content only
/// ```
public struct ContentMarginPlacement: Hashable, Sendable {
    enum Kind: UInt8, Sendable {
        case automatic, scrollContent, scrollIndicators
    }

    let kind: Kind

    /// Wherever the view applies margins by default — for a ``ScrollView``,
    /// both its content and its scroll indicators.
    public static var automatic: Self { Self(kind: .automatic) }

    /// A scroll view's content, and not its indicators.
    public static var scrollContent: Self { Self(kind: .scrollContent) }

    /// A scroll view's indicators, and not its content.
    public static var scrollIndicators: Self { Self(kind: .scrollIndicators) }
}

// MARK: - Environment

/// The content margins stated above a view, edge by edge, for each placement.
///
/// Edge by edge because that is how SwiftUI combines them (measured): an inner
/// `.contentMargins(.top, 20)` under an outer `.contentMargins(.horizontal,
/// 10)` gives 20 at the top AND 10 at the sides — the inner call overrides only
/// the edges it names. And per placement because the specific placement wins
/// over `.automatic` wherever either is written (measured both ways round), so
/// the two have to be kept apart until they are resolved.
package struct ContentMargins: Equatable, Sendable {
    /// One placement's stated edges; `nil` where nothing was stated.
    struct Edges: Equatable, Sendable {
        var top: Int?
        var leading: Int?
        var bottom: Int?
        var trailing: Int?

        var isEmpty: Bool {
            guard top == nil, leading == nil, bottom == nil else { return false }
            return trailing == nil
        }

        mutating func state(_ edges: Edge.Set, _ insets: EdgeInsets) {
            if edges.contains(.top) { top = insets.top }
            if edges.contains(.leading) { leading = insets.leading }
            if edges.contains(.bottom) { bottom = insets.bottom }
            if edges.contains(.trailing) { trailing = insets.trailing }
        }
    }

    var automatic = Edges()
    var scrollContent = Edges()
    var scrollIndicators = Edges()

    /// No margins stated, spelled out because the implicit initializer is
    /// internal and TUIkitForms makes these: a `Form` hands its rows a clean
    /// slate once it has applied its own.
    package init() {}

    /// Whether nothing was stated — the case every scroll view without margins
    /// is in, and tests first.
    package var isEmpty: Bool { automatic.isEmpty && scrollContent.isEmpty && scrollIndicators.isEmpty }

    /// Records a `contentMargins` call: `edges` of `insets`, for `placement`.
    mutating func state(_ edges: Edge.Set, _ insets: EdgeInsets, for placement: ContentMarginPlacement) {
        switch placement.kind {
        case .automatic: automatic.state(edges, insets)
        case .scrollContent: scrollContent.state(edges, insets)
        case .scrollIndicators: scrollIndicators.state(edges, insets)
        }
    }

    /// The margins around a scroll view's content: each edge's `.scrollContent`
    /// value, else its `.automatic` one, else none. Never negative.
    package var content: EdgeInsets { resolved(scrollContent) }

    /// The margins around a scroll view's indicators, resolved the same way
    /// from `.scrollIndicators` and `.automatic`.
    var indicators: EdgeInsets { resolved(scrollIndicators) }

    private func resolved(_ specific: Edges) -> EdgeInsets {
        EdgeInsets(
            top: max(0, specific.top ?? automatic.top ?? 0),
            leading: max(0, specific.leading ?? automatic.leading ?? 0),
            bottom: max(0, specific.bottom ?? automatic.bottom ?? 0),
            trailing: max(0, specific.trailing ?? automatic.trailing ?? 0))
    }
}

private struct ContentMarginsKey: EnvironmentKey {
    static let defaultValue = ContentMargins()
}

extension EnvironmentValues {
    /// The content margins stated above this view — see ``ContentMargins``.
    ///
    /// A scroll view consumes them: its content does not inherit them, so a
    /// scroll view nested in its content has none (measured on SwiftUI).
    package var contentMargins: ContentMargins {
        get { self[ContentMarginsKey.self] }
        set { self[ContentMarginsKey.self] = newValue }
    }
}

extension EdgeInsets {
    /// Whether every edge is zero — the margins that change nothing.
    package var isZero: Bool { top == 0 && leading == 0 && bottom == 0 && trailing == 0 }
}

// MARK: - Modifiers

extension View {
    /// Adds margins to `edges` of the views in this hierarchy that support
    /// them. Matches SwiftUI's `contentMargins(_:_:for:)`.
    ///
    /// A ``ScrollView`` keeps the margins inside its scrollable area, so they
    /// scroll with its content: scrolled to the top, the top margin shows above
    /// the first row; scrolled down, it has gone with it. Under `.automatic`
    /// the scroll indicators are inset too. A grouped ``Form`` pads its sections
    /// by them. `List`, `Table` and `TextEditor` do not apply them, as they do
    /// not on macOS (measured), and neither does a columns `Form`.
    ///
    /// Margins combine edge by edge: an inner call overrides the edges it names,
    /// and `.scrollContent` or `.scrollIndicators` overrides `.automatic` for
    /// its part, wherever either is written. A scroll view's content does not
    /// inherit them.
    ///
    /// - Parameters:
    ///   - edges: The edges to add margins to.
    ///   - insets: The margins, in cells; only `edges` of them are used.
    ///   - placement: Where the margins go.
    public func contentMargins(
        _ edges: Edge.Set = .all, _ insets: EdgeInsets,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        transformEnvironment(\.contentMargins) { $0.state(edges, insets, for: placement) }
    }

    /// Adds `length` cells of margin to `edges`. Matches SwiftUI's
    /// `contentMargins(_:_:for:)`; see the `EdgeInsets` form.
    ///
    /// - Parameters:
    ///   - edges: The edges to add margins to.
    ///   - length: The margin, in cells. `nil` is none, as it is in SwiftUI
    ///     (measured).
    ///   - placement: Where the margins go.
    public func contentMargins(
        _ edges: Edge.Set = .all, _ length: Int?,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        contentMargins(edges, EdgeInsets(all: length ?? 0), for: placement)
    }

    /// Adds `length` cells of margin on every edge. Matches SwiftUI's
    /// `contentMargins(_:for:)`.
    ///
    /// - Parameters:
    ///   - length: The margin, in cells.
    ///   - placement: Where the margins go.
    public func contentMargins(
        _ length: Int, for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        contentMargins(.all, EdgeInsets(all: length), for: placement)
    }
}

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// This scroll view drawing its content inside `margins`, or `nil` when it
    /// already does or has none.
    ///
    /// The margins are applied by drawing a copy of this view whose content is
    /// the margined content, so every place that measures or draws the content
    /// — the extents, the overflow probe, the ideal size, the render — sees the
    /// margins without being taught about them, and a view with none pays
    /// nothing but the test. The copy keeps this view's identity, so its
    /// handler and its state are this view's.
    ///
    /// It is this view in every other respect, so it carries every stored
    /// setting of this one: the copy does the whole render, and a setting it
    /// dropped was one the view lost whenever it had margins — a chrome
    /// scroller under a page's `.contentMargins` took the page's scroll target
    /// behaviour and drew its rows past its box under `scrollClipDisabled`.
    func margined(context: RenderContext) -> _ScrollViewCore<_ScrollContentMargins<Content>>? {
        guard !appliesContentMargins else { return nil }
        let margins = resolvedContentMargins(context.environment)
        guard !margins.isZero else { return nil }
        return _ScrollViewCore<_ScrollContentMargins<Content>>(
            axes: axes, content: _ScrollContentMargins(content: content, insets: margins),
            explicitFocusID: explicitFocusID, isDisabled: isDisabled,
            isFocusStop: isFocusStop, isChrome: isChrome, appliesContentMargins: true,
            hidesAutomaticIndicators: hidesAutomaticIndicators)
    }

    /// The margins around this view's scroll indicators — `.scrollIndicators`
    /// and the indicator half of `.automatic` (see ``ContentMargins``). Zero
    /// for almost every view, which pays one test for it.
    ///
    /// A bar is shortened along its own axis and moved in across it: a
    /// vertical bar by the top and bottom margins and the trailing one, a
    /// horizontal bar by the leading and trailing margins and the bottom one.
    /// That is where an overlay scroller goes under the same margins; here the
    /// bar is a column or row of the viewport, so the cells it moves in by are
    /// the content's to give up. The "N more" lines are lines of the viewport,
    /// not a scroller, and do not move.
    ///
    /// A `safeAreaPadding` on the view adds to them, as it does to the content's.
    /// A framework scroller has none (``resolvedContentMargins(_:)``).
    func indicatorMargins(_ context: RenderContext) -> EdgeInsets {
        guard !isChrome else { return EdgeInsets() }
        let margins = context.environment.contentMargins
        let stated = margins.isEmpty ? EdgeInsets() : margins.indicators
        return stated.adding(context.environment.safeAreaContentMargins)
    }

    /// The margins this view draws its content inside: its content margins
    /// and, added to them, a `safeAreaPadding` on the view along its scrolling
    /// axes (measured additive on SwiftUI).
    ///
    /// None for a framework scroller (``ScrollView/asChrome()``): the page's
    /// margins are for the page's scroll views, and the scroller around a menu
    /// or a dialog is there only when its content is too tall, so taking them
    /// inset an inline menu's rows only once it scrolled — and inside a width
    /// planned without them, so its labels wrapped. It passes them on to its
    /// content instead (``contentContext(_:)``), which lays out as it would
    /// without the scroller.
    func resolvedContentMargins(_ environment: EnvironmentValues) -> EdgeInsets {
        guard !isChrome else { return EdgeInsets() }
        let margins = environment.contentMargins
        let stated = margins.isEmpty ? EdgeInsets() : margins.content
        return stated.adding(environment.safeAreaContentMargins)
    }

    /// The viewport a render draws into — what it was given — the context
    /// with it published as the content's `containerRelativeFrame` container,
    /// the horizontal bar as known before the content is measured
    /// (``horizontalBarDecidedFirst(viewport:context:)``) and the "N more"
    /// pair at it, which the container was decided by and the render's chrome
    /// is decided by too (`resolveChrome`): asked once, so a scroll target
    /// behaviour's overflow measures are too. The context is the one this
    /// view reads, ``ScrollView/showsIndicators`` applied
    /// (``hidingAutomaticIndicators(_:)``), as everything after this does.
    func viewport(
        _ context: RenderContext
    ) -> (
        context: RenderContext, width: Int, height: Int, textLines: TextIndicatorLines, horizontalBar: Bool
    ) {
        let context = hidingAutomaticIndicators(context)
        let width = context.availableWidth
        let height = max(0, context.availableHeight)
        let size = CellSize(width: max(0, width), height: height)
        let bar = horizontalBarDecidedFirst(viewport: size, context: context)
        let textLines = textIndicatorLines(context, viewport: size, horizontalBar: bar)
        let container = containerSize(viewport: size, textLines: textLines, horizontalBar: bar, context: context)
        return (context.publishingContainerSize(container), width, height, textLines, bar)
    }

    /// The container size a `containerRelativeFrame` in the content sizes
    /// against: the viewport, less the content's margins, as SwiftUI's is
    /// (measured) — and less the "N more" lines when they are reserved out of
    /// the window the content is seen through, at every offset (under
    /// `.visible`, or a scroll target behaviour). Then the
    /// window is what the content is seen through, and is
    /// ``ScrollGeometry/containerSize`` and a scroll target behaviour's
    /// container too, so a page sized against it is the page `.paging` steps:
    /// sized against the viewport, ten-line pages in an eight-line window
    /// stopped two lines further into each page at every step.
    ///
    /// A horizontal bar's row (and its indicator margin) comes off it too
    /// where the bar is known before the container is published
    /// (``horizontalBarDecidedFirst(viewport:context:)``): `.visible`, which
    /// draws it always, or a pager's `.automatic` one, decided first by a
    /// measure of the content's width. The step takes the row off the window,
    /// so a page sized against the whole viewport was a line taller than the
    /// step and each stop showed a line more of the page before (scroll lane
    /// review 3). A scroll view with no behaviour decides an `.automatic` bar
    /// after the container is published, by measuring the content in it, so
    /// its container is the viewport's height whether the bar comes or not
    /// (decisions SCROLL B-SCROLL-2). The pair is asked with the bar as known
    /// here.
    func containerSize(viewport: CellSize, context: RenderContext) -> CellSize {
        let bar = horizontalBarDecidedFirst(viewport: viewport, context: context)
        return containerSize(
            viewport: viewport, textLines: textIndicatorLines(context, viewport: viewport, horizontalBar: bar),
            horizontalBar: bar, context: context)
    }

    /// ``containerSize(viewport:context:)`` with the bar and the pair at
    /// `viewport` already in hand.
    private func containerSize(
        viewport: CellSize, textLines: TextIndicatorLines, horizontalBar: Bool, context: RenderContext
    ) -> CellSize {
        let container = unreservedContainerSize(viewport: viewport, context: context)
        let (bar, barMargin) = horizontalBarRows(horizontalBar, context: context)
        let text = textLines.fitted(viewportHeight: viewport.height - barMargin, horizontalBar: bar)
        let taken = (bar ? 1 + barMargin : 0) + (text.reserved ? 2 : 0)
        guard taken > 0 else { return container }
        return CellSize(width: container.width, height: max(0, container.height - taken))
    }

    /// Whether this view's horizontal bar is drawn, as far as it is known
    /// before the content's container is published — and so whether its row
    /// comes off the container (``containerSize(viewport:context:)``) and the
    /// render's bar rounds start with it (`resolveScrollbars`).
    ///
    /// `.visible` draws it always. An `.automatic` one comes with overflow,
    /// and for a view under a scroll target behaviour that scrolls across — a
    /// pager — it is decided here, by a measure of the content's width at the
    /// whole viewport: wider, and the bar is drawn whatever else the rounds
    /// decide. Without it the container was the viewport's height and the
    /// bar's row came off only the window, so a two-axis pager's
    /// container-sized pages were a line taller than the step and drifted by
    /// it at each stop (decisions FU2 B-FU2-2). Content that fits the whole
    /// width and overflows only once a vertical bar takes its column is left
    /// for the rounds, and drifts as before.
    ///
    /// Only a pager pays the measure: elsewhere a container-sized page a line
    /// taller than the window is scrolled to like any other line (decisions
    /// SCROLL B-SCROLL-2). It is asked in a measure generation keyed by the
    /// height of the container it publishes, as
    /// ``contentOverflowsWindow(viewport:horizontalBar:context:)`` asks, so
    /// neither serves the render answers given under another container — and
    /// where no bar comes the two ask the same question and share the answer.
    func horizontalBarDecidedFirst(viewport: CellSize, context: RenderContext) -> Bool {
        guard axes.contains(.horizontal) else { return false }
        let visibility = context.environment.horizontalScrollIndicatorVisibility
        if visibility == .visible { return true }
        guard visibility == .automatic, scrollTargetBehaviorInForce(context.environment) != nil else {
            return false
        }
        let container = unreservedContainerSize(viewport: viewport, context: context)
        let probe = context.publishingContainerSize(container, noting: false)
            .invalidatingMeasureMemo(keyedBy: container.height)
        let width = max(1, viewport.width)
        return contentExtents(
            contentWidth: width, viewportHeight: viewport.height, horizontal: true, context: probe
        ).width > width
    }

    /// A horizontal bar `drawn` (``horizontalBarDecidedFirst(viewport:context:)``)
    /// and the indicator margin it moves in by, which comes off the window
    /// with it, as `resolveChrome` takes them.
    private func horizontalBarRows(_ drawn: Bool, context: RenderContext) -> (drawn: Bool, margin: Int) {
        drawn ? (true, indicatorMargins(context).bottom) : (false, 0)
    }

    /// The container with nothing reserved out of it: the viewport less the
    /// content's margins.
    private func unreservedContainerSize(viewport: CellSize, context: RenderContext) -> CellSize {
        guard appliesContentMargins else { return viewport }
        let margins = resolvedContentMargins(context.environment)
        return CellSize(
            width: max(0, viewport.width - margins.leading - margins.trailing),
            height: max(0, viewport.height - margins.top - margins.bottom))
    }

    /// Whether the content is taller than `viewport` seen whole — nothing
    /// reserved out of it, and the content's pages sized against that
    /// unreserved container: whether a scroll target behaviour reserves the
    /// "N more" pair (``textIndicatorLines(_:viewport:horizontalBar:)``).
    ///
    /// On the content's height alone, never the offset, so the answer is the
    /// same at every stop; and on the whole window, so content sized against
    /// the container answers as it will be drawn — pages as tall as the whole
    /// window that overflow it overflow the window less the pair as well, and
    /// one page that fits it is drawn unreserved and fits. The window is the
    /// one ``containerSize(viewport:context:)`` leaves when it reserves
    /// nothing: less a horizontal bar known to be drawn (`horizontalBar`), its
    /// row and its indicator margin. Asked of the whole viewport, content that
    /// overflowed the window by no more than the bar's row reserved nothing,
    /// and its pair was drawn over the window's edge lines under a behaviour
    /// that lands steps in it.
    ///
    /// A measure of the content, paid only by a text-style view under a
    /// behaviour (the free one, the default, asks nothing), in a measure
    /// generation of its own for each height of the container it publishes
    /// (``RenderContext/invalidatingMeasureMemo(keyedBy:)``).
    /// The render then measures the content again at the same proposal, and
    /// where it reserves, against a container two lines shorter — a different
    /// question that the measure memos' keys cannot tell apart, since they
    /// leave the environment out. Sharing a generation, the pass's memo and the
    /// memoised rows' cross-frame sizes served the probe's pages to the render:
    /// five window-sized pages measured ten lines each where they were drawn
    /// eight, and the canvas was ten lines too tall. Apart, the probe's answers
    /// still serve the probe, frame after frame; the price is that a view
    /// reserving nothing is no longer served the probe's measure for its own.
    ///
    /// And apart from the probe's own answers at another height: neither memo
    /// key carries the container either, so a parent that measured the scroll
    /// view at one height and drew it at another — a title above it in a
    /// stack — served the draw's probe the measure's pages, a window's worth
    /// too tall, and one page that fits reserved the pair.
    func contentOverflowsWindow(viewport: CellSize, horizontalBar: Bool, context: RenderContext) -> Bool {
        let (bar, barMargin) = horizontalBarRows(horizontalBar, context: context)
        let barRows = bar ? 1 + barMargin : 0
        let container = unreservedContainerSize(viewport: viewport, context: context)
        let probeHeight = max(0, container.height - barRows)
        let probe = context.publishingContainerSize(
            CellSize(width: container.width, height: probeHeight), noting: false
        ).invalidatingMeasureMemo(keyedBy: probeHeight)
        let width = max(1, viewport.width)
        let window = max(0, viewport.height - barRows)
        guard axes.contains(.horizontal) else {
            return contentOverflowsCanvas(contentWidth: width, viewportHeight: window, context: probe)
        }
        return contentExtents(
            contentWidth: width, viewportHeight: window, horizontal: true, context: probe
        ).height > window
    }
}

// MARK: - The margined content

/// A scroll view's content inside its content margins: blank lines above and
/// below it, blank columns either side, all scrolling with it.
///
/// Drawn at the content's own identity, as `Section` draws its content, so the
/// content's state and a lazy stack's claim on the scroll window are what they
/// would be without margins; the window is relayed below the top margin
/// (``ScrollWindowRelay``), so the stack still bands itself, seeks and reports
/// its row.
struct _ScrollContentMargins<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let insets: EdgeInsets

    var body: Never { fatalError("_ScrollContentMargins renders via Renderable") }

    /// The leading and trailing margins that fit `width`: never the content's
    /// last column, which the content keeps — the rule padding follows, for
    /// its reason. A vertical scroll view's lines are as wide as its viewport,
    /// so a margin that did not fit would make a line wider than the view.
    private func sides(in width: Int) -> (leading: Int, trailing: Int) {
        let room = max(0, width - 1)
        let leading = min(insets.leading, room)
        return (leading, min(insets.trailing, room - leading))
    }

    /// The context the content gets: what is left inside the margins.
    private func innerContext(_ context: RenderContext, sides: (leading: Int, trailing: Int)) -> RenderContext {
        var inner = context
        inner.availableWidth = max(0, context.availableWidth - sides.leading - sides.trailing)
        inner.availableHeight = max(0, context.availableHeight - insets.top - insets.bottom)
        return inner
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let sides = sides(in: proposal.width ?? context.availableWidth)
        let across = sides.leading + sides.trailing
        let along = insets.top + insets.bottom
        let size = measureChild(
            content,
            proposal: ProposedSize(
                width: proposal.width.map { max(0, $0 - across) },
                height: proposal.height.map { max(0, $0 - along) }),
            context: innerContext(context, sides: sides))
        return ViewSize(
            width: Self.adding(size.width, across), height: Self.adding(size.height, along),
            isWidthFlexible: size.isWidthFlexible, isHeightFlexible: size.isHeightFlexible)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let sides = sides(in: context.availableWidth)
        let inner = innerContext(context, sides: sides)
        // A lazy stack in the content bands itself against the scroll window,
        // which has to be moved below the top margin first.
        let relay = ScrollWindowRelay(
            context: context, linesAbove: insets.top, linesBelow: { insets.bottom })
        // And the column a horizontal view reports sampled past the leading
        // margin, in the content's coordinates.
        let buffer = TUIkitView.renderToBuffer(
            content, context: (relay?.contentContext(inner) ?? inner).withScrollWindowAcross(leading: sides.leading))
        // A band that starts below the content's top leaves the top margin out
        // of the buffer, and one that stops above its end the bottom margin.
        let placement =
            relay?.answer(contentBuffer: buffer, linesBelow: insets.bottom)
            ?? ScrollWindowRelay.Placement()
        let top = placement.drawsAbove ? insets.top : 0
        let bottom = placement.drawsBelow ? insets.bottom : 0
        // The columns the content answered, moved across by the leading
        // margin: the relay moves the content only down, and without one (no
        // top or bottom margin) the content answered the scroll view's reply
        // itself.
        if sides.leading > 0 { context.environment.scrollContentWindow?.reply?.shiftColumns(by: sides.leading) }

        let width = buffer.width + sides.leading + sides.trailing
        let blank = String(asciiSpaces(width))
        var lines: [String] = []
        lines.reserveCapacity(top + buffer.lines.count + bottom)
        lines.append(contentsOf: repeatElement(blank, count: top))
        for line in buffer.lines {
            var padded = ""
            padded.reserveCapacity(line.utf8.count + sides.leading + sides.trailing)
            if sides.leading > 0 { padded += asciiSpaces(sides.leading) }
            padded += line
            if sides.trailing > 0 { padded += asciiSpaces(sides.trailing) }
            lines.append(padded)
        }
        lines.append(contentsOf: repeatElement(blank, count: bottom))
        // Uniform exactly when the content's lines were, as padding's are.
        return buffer.replacingLines(
            lines, width: width, uniformWidth: buffer.linesAreUniformWidth,
            overlayShiftX: sides.leading, overlayShiftY: top)
    }

    /// `a + b`, saturating: a measure offered the whole of `Int` can answer it.
    private static func adding(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : sum
    }
}

/// Names the app's own content type inside the margins, which is the type the
/// content's identity is made from (`_ScrollViewCore.contentContext`).
@MainActor
protocol MarginedScrollContent {
    static var appContentType: Any.Type { get }
}

extension _ScrollContentMargins: MarginedScrollContent {
    static var appContentType: Any.Type { Content.self }
}
