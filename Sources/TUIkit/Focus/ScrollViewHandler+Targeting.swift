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
    /// The visible area is what can be READ. Under the "N more" lines drawn
    /// over the viewport's first and last line (``textIndicatorInset``) that is
    /// the band between them: ``pageDistance`` lines, starting a line below the
    /// offset — Page Down's page, for the reason it is Page Down's. Handed the
    /// whole viewport, `.paging` stepped a full viewport and left the two lines
    /// under the indicators at every boundary unreadable at every stop, and
    /// `.viewAligned` landed each row's first line under "▲ N more". At the top
    /// and bottom, where one indicator is not drawn, the band is a line short of
    /// what shows; the safe direction, as it is for Page Down.
    func targetedOffsets(proposedX: Int, proposedY: Int, velocity: CellVector) -> (x: Int, y: Int)? {
        guard let targeting = scrollTargeting else { return nil }
        let inset = textIndicatorInset
        let scrollsAcross = targeting.axes.contains(.horizontal)
        let container = CellSize(
            width: scrollsAcross ? horizontal.viewportHeight : targeting.width, height: pageDistance)
        let original = ScrollTarget(
            rect: CellRect(
                x: horizontal.scrollOffset, y: scrollOffset + inset,
                width: container.width, height: container.height))
        var target = original
        target.rect.x = proposedX
        target.rect.y = proposedY + inset
        let context = ScrollTargetBehaviorContext(
            originalTarget: original, velocity: velocity,
            contentSize: CellSize(width: scrollsAcross ? horizontal.extent : targeting.width, height: contentHeight),
            containerSize: container, axes: targeting.axes, environment: targeting.environment,
            targetLayoutRows: targeting.rows, targetLayoutColumns: targeting.columns)
        targeting.behavior.updateTarget(&target, context: context)
        let anchor = target.anchor ?? .topLeading
        return (
            x: target.rect.x + Int((anchor.x * Double(target.rect.width - container.width)).rounded(.down)),
            y: target.rect.y - inset
                + Int((anchor.y * Double(target.rect.height - container.height)).rounded(.down))
        )
    }

    /// The vertical step a user scroll of `delta` lines takes
    /// (``ScrollableOffsetState`` requirement). A behaviour that also moved the
    /// target across moves the horizontal axis with it.
    public func userScrollStep(_ delta: Int) -> Int {
        guard delta != 0,
            let landed = targetedOffsets(
                proposedX: horizontal.scrollOffset, proposedY: scrollOffset + delta,
                velocity: CellVector(dx: 0, dy: Double(delta)))
        else { return delta }
        if landed.x != horizontal.scrollOffset { horizontal.scrollToOffset(landed.x) }
        return landed.y - scrollOffset
    }

    /// The horizontal step a user scroll of `delta` columns takes — what the
    /// horizontal axis asks (``ScrollAxis/stepTargeting``). A behaviour that
    /// also moved the target down moves the vertical axis with it.
    func horizontalUserScrollStep(_ delta: Int) -> Int {
        guard delta != 0,
            let landed = targetedOffsets(
                proposedX: horizontal.scrollOffset + delta, proposedY: scrollOffset,
                velocity: CellVector(dx: Double(delta), dy: 0))
        else { return delta }
        if landed.y != scrollOffset { scrollToOffset(landed.y) }
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

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// Captures the scroll target behaviour in force onto the handler, for the
    /// steps it lands at event time — or clears it, when there is none.
    ///
    /// The width and the target layout's rows are kept from the last frame
    /// that recorded them (``recordTargetingGeometry(handler:contentWidth:)``,
    /// and the content's reply), so a measure pass, which records neither,
    /// leaves them as the last drawn frame had them.
    func captureScrollTargeting(handler: ScrollViewHandler, context: RenderContext) {
        let behavior = context.environment.scrollTargetBehavior
        guard !(behavior is _FreeScrollTargetBehavior) else {
            if handler.scrollTargeting != nil { handler.scrollTargeting = nil }
            return
        }
        let previous = handler.scrollTargeting
        handler.scrollTargeting = ScrollViewTargeting(
            behavior: behavior, axes: axes, environment: context.environment.detachedFromRuntime(),
            width: previous?.width ?? 0, rows: previous?.rows ?? .none, columns: previous?.columns ?? .none)
    }

    /// Records the width a drawn frame settled on, for a behaviour's context.
    /// Render passes only, from `finishFrame`.
    func recordTargetingGeometry(handler: ScrollViewHandler, contentWidth: Int) {
        guard handler.scrollTargeting != nil else { return }
        handler.scrollTargeting?.width = contentWidth
    }
}
