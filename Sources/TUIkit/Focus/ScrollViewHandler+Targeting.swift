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
    /// environment.
    let behavior: any ScrollTargetBehavior
    let axes: Axis.Set
    let environment: EnvironmentValues

    /// The width the content is seen through, and the content's whole width,
    /// as the last frame drew them.
    var containerWidth = 0
    var contentWidth = 0

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
    func targetedOffsets(proposedX: Int, proposedY: Int, velocity: CellVector) -> (x: Int, y: Int)? {
        guard let targeting = scrollTargeting else { return nil }
        let container = CellSize(width: targeting.containerWidth, height: viewportHeight)
        let original = ScrollTarget(
            rect: CellRect(
                x: horizontal.scrollOffset, y: scrollOffset,
                width: container.width, height: container.height))
        var target = original
        target.rect.x = proposedX
        target.rect.y = proposedY
        let context = ScrollTargetBehaviorContext(
            originalTarget: original, velocity: velocity,
            contentSize: CellSize(width: targeting.contentWidth, height: contentHeight),
            containerSize: container, axes: targeting.axes, environment: targeting.environment,
            targetLayoutRows: targeting.rows, targetLayoutColumns: targeting.columns)
        targeting.behavior.updateTarget(&target, context: context)
        let anchor = target.anchor ?? .topLeading
        return (
            x: target.rect.x + Int((anchor.x * Double(target.rect.width - container.width)).rounded(.down)),
            y: target.rect.y + Int((anchor.y * Double(target.rect.height - container.height)).rounded(.down))
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
        guard
            let landed = targetedOffsets(
                proposedX: horizontal.scrollOffset, proposedY: scrollOffset, velocity: .zero)
        else { return }
        if landed.y != scrollOffset { scrollToOffset(landed.y) }
        if landed.x != horizontal.scrollOffset { horizontal.scrollToOffset(landed.x) }
    }
}

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// Captures the scroll target behaviour in force onto the handler, for the
    /// steps it lands at event time — or clears it, when there is none.
    ///
    /// The widths and the target layout's rows are kept from the last frame
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
            behavior: behavior, axes: axes, environment: context.environment,
            containerWidth: previous?.containerWidth ?? 0, contentWidth: previous?.contentWidth ?? 0,
            rows: previous?.rows ?? .none, columns: previous?.columns ?? .none)
    }

    /// Records the widths a drawn frame settled on, for a behaviour's context.
    /// Render passes only, from `finishFrame`.
    func recordTargetingGeometry(handler: ScrollViewHandler, contentWidth: Int) {
        guard handler.scrollTargeting != nil else { return }
        handler.scrollTargeting?.containerWidth = contentWidth
        handler.scrollTargeting?.contentWidth =
            axes.contains(.horizontal) ? handler.horizontal.extent : contentWidth
    }
}
