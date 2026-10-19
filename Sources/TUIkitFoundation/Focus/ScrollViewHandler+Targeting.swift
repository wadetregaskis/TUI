//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollViewHandler+Targeting.swift
//
//  How a `ScrollView` lands its user's steps under a scroll target behaviour
//  (`.scrollTargetBehavior(_:)`): each step proposes a target, the behaviour
//  moves it, and the view goes where the behaviour put it.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What a ``ScrollView``'s render captured of the scroll target behaviour in
/// force, for the steps its handler lands at event time, when the environment
/// is out of reach. `nil` on the handler when there is none, which is what
/// every scroll view without one pays: one test a step.
struct ScrollViewTargeting {
    /// The behaviour, and what its contexts read: the scroll view's axes and
    /// environment — without the framework's own objects
    /// (``EnvironmentValues/detachedFromRuntime()``). The handler is in the
    /// state storage, and the environment whole holds the storage, the render
    /// cache, the focus manager and the dispatchers: kept here, it was a cycle
    /// that outlived the app.
    let behavior: any ScrollTargetBehavior
    let axes: Axis.Set
    let environment: EnvironmentValues

    /// The width a view that does not scroll across shows its content at, as
    /// the last frame drew it — its container's width and its content's both.
    /// A view that does scroll across reads its horizontal axis instead
    /// (``ScrollViewHandler/targetedOffsets(proposedX:proposedY:velocity:)``),
    /// which the render syncs before anything consults the behaviour, so a
    /// resize settles to the new width rather than the last frame's.
    var width = 0

    /// The rows of the content's scroll target layout, as the last frame
    /// reported them (``ScrollContentReply/targetLayoutRows``), and its
    /// columns (``ScrollContentReply/targetLayoutColumns``).
    var rows: TargetLayoutSpans = .none
    var columns: TargetLayoutSpans = .none

    /// The content margins the content is drawn inside (zero for a view with
    /// none): a behaviour sees the content without them, through the window
    /// less them, as SwiftUI's does
    /// (``ScrollViewHandler/targetedOffsets(proposedX:proposedY:velocity:)``).
    var margins = EdgeInsets()
}

extension ScrollViewHandler {
    /// Where a user scroll that would end at (`proposedX`, `proposedY`) comes
    /// to rest under the scroll target behaviour, or `nil` when there is none.
    ///
    /// The target is the visible area at the proposed offsets; the behaviour
    /// moves it, and the view scrolls so that the target's rect meets the
    /// visible area at the target's anchor — the top-leading corner when it
    /// names none. The offsets are not clamped here: the step that moves there
    /// clamps them, as it clamps any step.
    ///
    /// The visible area is the content window, every line of which can be
    /// read: under a behaviour the "N more" lines are reserved out of it at
    /// every offset, as under `.visible`, rather than drawn over its first and
    /// last line, wherever the content overflows (content that fits has none,
    /// and nowhere to step) — see ``_ScrollViewCore/textIndicatorLines(_:viewport:horizontalBar:)``.
    /// So the window is
    /// the same at every stop — the container a page is sized against, and the
    /// page `.paging` steps — and a row `.viewAligned` lands on is read whole.
    ///
    /// Under content margins the behaviour is handed SwiftUI's coordinates
    /// (measured on macOS 15, `Tools/SwiftUIProbes/Scroll target
    /// behaviours/`): the container is the window less the margins, the
    /// content its size without them, and the target the area inside them,
    /// with the content's first line at 0 — which is the scroll offset, since
    /// offset 0 shows the top margin above that line. So a page lands inside
    /// the margins, and a view aligned to the top lands at the top margin with
    /// the one before it showing in the margin.
    func targetedOffsets(proposedX: Int, proposedY: Int, velocity: CellVector) -> (x: Int, y: Int)? {
        guard let targeting = scrollTargeting else { return nil }
        let scrollsAcross = targeting.axes.contains(.horizontal)
        let margins = targeting.margins
        let across = margins.leading + margins.trailing
        let along = margins.top + margins.bottom
        let container = CellSize(
            width: max(0, (scrollsAcross ? horizontal.viewportHeight : targeting.width) - across),
            height: max(0, viewportHeight - along))
        let original = ScrollTarget(
            rect: CellRect(
                x: horizontal.scrollOffset, y: scrollOffset,
                width: container.width, height: container.height))
        var target = original
        target.rect.x = proposedX
        target.rect.y = proposedY
        let content = CellSize(
            width: max(0, (scrollsAcross ? horizontal.extent : targeting.width) - across),
            height: max(0, contentHeight - along))
        let context = ScrollTargetBehaviorContext(
            originalTarget: original, velocity: velocity, contentSize: content,
            containerSize: container, axes: targeting.axes, environment: targeting.environment,
            targetLayoutRows: targeting.rows.shifted(by: -margins.top),
            targetLayoutColumns: targeting.columns.shifted(by: -margins.leading))
        targeting.behavior.updateTarget(&target, context: context)
        let anchor = target.anchor ?? .topLeading
        return (
            x: target.rect.x + Int((anchor.x * Double(target.rect.width - container.width)).rounded(.down)),
            y: target.rect.y + Int((anchor.y * Double(target.rect.height - container.height)).rounded(.down))
        )
    }

    /// The vertical step a user scroll of `delta` lines takes
    /// (``ScrollableOffsetState`` requirement). A behaviour that also moved the
    /// target across moves the horizontal axis with it, which the step's caller
    /// sees (``acrossScrollOffset``).
    ///
    /// A view that does not scroll down asks no behaviour, so a vertical tick
    /// over a horizontal pager settles nothing and passes on.
    public func userScrollStep(_ delta: Int) -> Int {
        guard delta != 0, scrollTargeting?.axes.contains(.vertical) == true,
            let landed = targetedOffsets(
                proposedX: horizontal.scrollOffset, proposedY: scrollOffset + delta,
                velocity: CellVector(dx: 0, dy: Double(delta)))
        else { return delta }
        if landed.x != horizontal.scrollOffset { horizontal.scrollToOffset(landed.x) }
        return landed.y - scrollOffset
    }

    /// The horizontal step a user scroll of `delta` columns takes — what the
    /// horizontal axis asks (``ScrollAxis/stepTargeting``). A behaviour that
    /// also moved the target down moves the vertical axis with it, and that is
    /// the user scrolling the rows: a bound anchor is released, as by any
    /// user scroll (``releaseAnchorOnUserScroll()``). Left alone, the binding
    /// went on naming the row the user had just scrolled off.
    ///
    /// A view that does not scroll across asks no behaviour: Left on a
    /// vertical pager used to settle its rows.
    func horizontalUserScrollStep(_ delta: Int) -> Int {
        guard delta != 0, scrollTargeting?.axes.contains(.horizontal) == true,
            let landed = targetedOffsets(
                proposedX: horizontal.scrollOffset + delta, proposedY: scrollOffset,
                velocity: CellVector(dx: Double(delta), dy: 0))
        else { return delta }
        if landed.y != scrollOffset {
            scrollToOffset(landed.y)
            releaseAnchorOnUserScroll()
        }
        return landed.x - horizontal.scrollOffset
    }

    /// Settles a gesture that ended where it is (``ScrollableOffsetState``
    /// requirement): both axes go where the behaviour puts the visible area.
    public func settleUserScroll() {
        settle([.horizontal, .vertical])
    }

    /// Puts `axes` where the behaviour puts the visible area as it is, as a
    /// gesture with no velocity; the other axis stays where it is.
    func settle(_ axes: Axis.Set) {
        guard
            let landed = targetedOffsets(
                proposedX: horizontal.scrollOffset, proposedY: scrollOffset, velocity: .zero)
        else { return }
        if axes.contains(.vertical), landed.y != scrollOffset { scrollToOffset(landed.y) }
        if axes.contains(.horizontal), landed.x != horizontal.scrollOffset {
            horizontal.scrollToOffset(landed.x)
        }
    }
}

extension ScrollViewHandler {
    /// The horizontal offset, for a vertical step to tell whether a behaviour
    /// moved it (``ScrollableOffsetState`` requirement).
    public var acrossScrollOffset: Int { horizontal.scrollOffset }
}

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// Captures the scroll target behaviour in force onto the handler, for the
    /// steps it lands at event time — or clears it, when there is none.
    ///
    /// The width and the target layout's rows are kept from the last frame
    /// that recorded them (``recordTargetingGeometry(handler:contentWidth:)``,
    /// and the content's reply), so a measure pass, which records neither,
    /// leaves them as the last drawn frame had them.
    ///
    /// The framework's own scrollers (``ScrollView/asChrome()``) — a tall
    /// menu's column, a sheet's or a framed container's content — take no
    /// behaviour: the page's `.paging` is for the page's scroll views, and
    /// paged an inline menu's rows a screenful a wheel tick.
    func captureScrollTargeting(handler: ScrollViewHandler, context: RenderContext) {
        guard let behavior = scrollTargetBehaviorInForce(context.environment) else {
            if handler.scrollTargeting != nil { handler.scrollTargeting = nil }
            return
        }
        let previous = handler.scrollTargeting
        handler.scrollTargeting = ScrollViewTargeting(
            behavior: behavior, axes: axes, environment: context.environment.detachedFromRuntime(),
            width: previous?.width ?? 0, rows: previous?.rows ?? .none, columns: previous?.columns ?? .none,
            margins: appliesContentMargins ? resolvedContentMargins(context.environment) : EdgeInsets())
    }

    /// The scroll target behaviour this view lands its user's steps under, or
    /// `nil`: none stated (the free one, the default), or a framework scroller,
    /// which takes none (``captureScrollTargeting(handler:context:)``). One
    /// predicate, because the "N more" lines are reserved under exactly the
    /// behaviours the steps are landed by (``textIndicatorLines(_:viewport:horizontalBar:)``).
    func scrollTargetBehaviorInForce(_ environment: EnvironmentValues) -> (any ScrollTargetBehavior)? {
        guard !isChrome else { return nil }
        let behavior = environment.scrollTargetBehavior
        return behavior is _FreeScrollTargetBehavior ? nil : behavior
    }

    /// Records the width a drawn frame settled on, for a behaviour's context.
    /// Render passes only, from `finishFrame`.
    func recordTargetingGeometry(handler: ScrollViewHandler, contentWidth: Int) {
        guard handler.scrollTargeting != nil else { return }
        handler.scrollTargeting?.width = contentWidth
    }
}
